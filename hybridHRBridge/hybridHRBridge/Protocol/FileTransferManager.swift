import Foundation
import Combine
import CoreBluetooth

/// Manages file transfers to/from Fossil Hybrid HR watch
/// Handles the file put/get protocol over BLE characteristics
/// Source: FilePutRawRequest.java, FileGetRawRequest.java
@MainActor
final class FileTransferManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isTransferring = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastError: FileTransferError?
    
    // MARK: - Types
    
    enum TransferState {
        case idle
        case sendingHeader
        case sendingData
        case awaitingAck
        case closing
        case complete
        case failed
    }
    
    // MARK: - Private Properties
    
    private let bluetoothManager: BluetoothManager
    private let authManager: AuthenticationManager
    
    private var transferState: TransferState = .idle
    private var currentData: Data?
    private var currentHandle: FileHandle?
    private var bytesSent: Int = 0
    private var transferContinuation: CheckedContinuation<Void, Error>?
    
    // MTU for data packets (iOS typically negotiates 185-517)
    // Leave room for BLE overhead
    private var mtuSize: Int = 180
    
    // MARK: - Initialization
    
    init(bluetoothManager: BluetoothManager, authManager: AuthenticationManager) {
        self.bluetoothManager = bluetoothManager
        self.authManager = authManager
    }
    
    // MARK: - Public API
    
    /// Put a file to the watch
    /// - Parameters:
    ///   - data: The file data to transfer
    ///   - handle: The file handle destination
    ///   - encrypted: Whether to use encrypted transfer (requires authentication)
    func putFile(_ data: Data, to handle: FileHandle, encrypted: Bool = false) async throws {
        guard !isTransferring else {
            throw FileTransferError.transferInProgress
        }
        
        guard authManager.isAuthenticated || !encrypted else {
            throw FileTransferError.notAuthenticated
        }
        
        isTransferring = true
        progress = 0
        currentData = data
        currentHandle = handle
        bytesSent = 0
        transferState = .sendingHeader
        
        defer {
            isTransferring = false
            currentData = nil
            currentHandle = nil
        }
        
        // Register response handler
        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicFileOperations) { [weak self] response in
            Task { @MainActor in
                self?.handleFileResponse(response)
            }
        }
        
        // Build and send file put header
        let header = RequestBuilder.buildFilePutRequest(handle: handle, data: data)
        BridgeLogger.shared.log("[FileTransfer] Sending PUT header for \(handle): \(header.hexString)")
        
        try await bluetoothManager.write(
            data: header,
            to: FossilConstants.characteristicFileOperations
        )
        
        transferState = .awaitingAck
        
        // Wait for transfer to complete
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.transferContinuation = continuation
            
            // Set timeout (30 seconds for large files)
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                if self.isTransferring {
                    self.transferContinuation?.resume(throwing: FileTransferError.timeout)
                    self.transferContinuation = nil
                    self.transferState = .failed
                }
            }
        }
        
        BridgeLogger.shared.log("[FileTransfer] Transfer complete!")
    }
    
    /// Send a notification to the watch
    func sendNotification(
        type: NotificationType,
        title: String,
        sender: String,
        message: String,
        appIdentifier: String
    ) async throws {
        let payload = RequestBuilder.buildNotification(
            type: type,
            title: title,
            sender: sender,
            message: message,
            packageCRC: appIdentifier.crc32,
            messageID: UInt32.random(in: 0...UInt32.max)
        )
        
        try await putFile(payload, to: .notificationPlay)
    }
    
    /// Sync time to the watch
    func syncTime(date: Date = Date(), timeZone: TimeZone = .current) async throws {
        let configData = RequestBuilder.buildTimeSyncRequest(date: date, timeZone: timeZone)
        
        // Time sync uses the configuration file handle
        try await putFile(configData, to: .configuration)
        
        BridgeLogger.shared.log("[FileTransfer] Time synced to \(date)")
    }
    
    /// Install a watch app (.wapp file)
    func installApp(wappData: Data) async throws {
        // The .wapp format already includes the file handle header
        // We just need to send it to the APP_CODE handle
        try await putFile(wappData, to: .appCode)
        
        BridgeLogger.shared.log("[FileTransfer] App installed (\(wappData.count) bytes)")
    }
    
    // MARK: - Private Methods
    
    private func handleFileResponse(_ data: Data) {
        guard data.count >= 1 else { return }
        
        let responseType = data[0] & 0x0F
        
        BridgeLogger.shared.log("[FileTransfer] Response type: \(String(format: "0x%02X", responseType)), data: \(data.hexString)")
        
        switch responseType {
        case FossilConstants.ResponseType.filePutInit.rawValue:
            // Ready to receive data
            handlePutInitResponse(data)
            
        case FossilConstants.ResponseType.dataAck.rawValue:
            // Data chunk acknowledged
            handleDataAck(data)
            
        case FossilConstants.ResponseType.fileComplete.rawValue:
            // Transfer complete
            handleTransferComplete(data)
            
        case FossilConstants.ResponseType.continuation.rawValue:
            // Continue sending
            continueDataTransfer()
            
        default:
            BridgeLogger.shared.log("[FileTransfer] Unknown response type: \(responseType)")
        }
    }
    
    private func handlePutInitResponse(_ data: Data) {
        guard data.count >= 4 else {
            failTransfer(with: .invalidResponse)
            return
        }
        
        // Check result code
        let resultCode = data[3]
        if resultCode != 0 {
            if let code = FossilConstants.ResultCode(rawValue: resultCode) {
                BridgeLogger.shared.log("[FileTransfer] PUT init failed: \(code)")
            }
            failTransfer(with: .rejected(resultCode))
            return
        }
        
        BridgeLogger.shared.log("[FileTransfer] PUT init accepted, starting data transfer")
        transferState = .sendingData
        continueDataTransfer()
    }
    
    private func handleDataAck(_ data: Data) {
        // Continue sending more data
        continueDataTransfer()
    }
    
    private func handleTransferComplete(_ data: Data) {
        guard data.count >= 4 else {
            failTransfer(with: .invalidResponse)
            return
        }
        
        let resultCode = data[3]
        if resultCode == 0 {
            transferState = .complete
            progress = 1.0
            transferContinuation?.resume()
            transferContinuation = nil
        } else {
            failTransfer(with: .rejected(resultCode))
        }
    }
    
    private func continueDataTransfer() {
        guard let data = currentData else { return }
        
        let remaining = data.count - bytesSent
        if remaining <= 0 {
            // All data sent, wait for completion
            transferState = .closing
            return
        }
        
        // Calculate chunk size
        let chunkSize = min(remaining, mtuSize - 1)  // -1 for packet header
        let isLastChunk = (bytesSent + chunkSize) >= data.count
        
        // Build data packet
        var packet = Data(capacity: chunkSize + 1)
        packet.append(isLastChunk ? 0x81 : 0x01)  // 0x80 bit = last packet
        packet.append(data.subdata(in: bytesSent..<(bytesSent + chunkSize)))
        
        bytesSent += chunkSize
        progress = Double(bytesSent) / Double(data.count)
        
        BridgeLogger.shared.log("[FileTransfer] Sending chunk: \(bytesSent)/\(data.count) bytes (\(Int(progress * 100))%)")
        
        // Send to file data characteristic
        Task {
            do {
                try await bluetoothManager.write(
                    data: packet,
                    to: FossilConstants.characteristicFileData,
                    type: .withoutResponse  // Use without response for speed
                )
            } catch {
                failTransfer(with: .writeFailed(error))
            }
        }
    }
    
    private func failTransfer(with error: FileTransferError) {
        lastError = error
        transferState = .failed
        transferContinuation?.resume(throwing: error)
        transferContinuation = nil
    }
}

// MARK: - Errors

enum FileTransferError: Error, LocalizedError {
    case transferInProgress
    case notAuthenticated
    case invalidResponse
    case timeout
    case rejected(UInt8)
    case writeFailed(Error)
    case fileTooLarge
    
    var errorDescription: String? {
        switch self {
        case .transferInProgress:
            return "A transfer is already in progress"
        case .notAuthenticated:
            return "Authentication required for this operation"
        case .invalidResponse:
            return "Invalid response from watch"
        case .timeout:
            return "Transfer timed out"
        case .rejected(let code):
            return "Transfer rejected by watch (code: \(code))"
        case .writeFailed(let error):
            return "Write failed: \(error.localizedDescription)"
        case .fileTooLarge:
            return "File is too large for the watch"
        }
    }
}
