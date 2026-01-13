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
    private let encryptedFileReader: EncryptedFileReader
    private let logger = LogManager.shared

    /// Flag to track if an operation is in progress
    @Published private(set) var isOperationInProgress = false

    private var transferState: TransferState = .idle
    private var currentData: Data?
    private var currentHandle: FileHandle?
    private var bytesSent: Int = 0
    private var packetIndex: UInt8 = 0
    private var fullCRC32: UInt32 = 0
    private var transferContinuation: CheckedContinuation<Void, Error>?

    // MTU for data packets (iOS typically negotiates 185-517)
    // Leave room for BLE overhead
    private var mtuSize: Int = 180

    // MARK: - Initialization

    init(bluetoothManager: BluetoothManager, authManager: AuthenticationManager) {
        self.bluetoothManager = bluetoothManager
        self.authManager = authManager
        self.encryptedFileReader = EncryptedFileReader(bluetoothManager: bluetoothManager, authManager: authManager)
    }

    // MARK: - Public API

    /// Initialize the file operations channel with a file lookup request (command 0x02)
    /// HR watches use FileLookupRequest BEFORE authentication for listApplications()
    /// Source: FossilHRWatchAdapter.java#L263 - listApplications() calls ApplicationsListRequest
    /// Source: ApplicationsListRequest.java - extends FileLookupAndGetRequest (command 0x02)
    /// This initializes the 0x02 command pathway before authentication
    func initializeFileOperations() async throws {
        logger.info("Protocol", "Initializing file operations channel with file lookup (command 0x02)...")

        // Send a FileLookupRequest (command 0x02) for APP_CODE like listApplications() does
        // This is what Gadgetbridge does BEFORE authentication to initialize the 0x02 command pathway
        // Source: FileLookupRequest.java - getStartSequence returns {2, 0xFF}
        // Payload: [0x02] [0xFF] [major]
        let appCodeHandle = FileHandle.appCode
        let request = Data([0x02, 0xFF, appCodeHandle.major])

        logger.debug("Protocol", "App list lookup request: \(request.hexString)")

        // Track if we get any responses
        var responsesReceived = 0

        // Register handler to receive the lookup response
        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicFileOperations) { [weak self] data in
            self?.logger.debug("Protocol", "📥 Init response on 3dda0003: \(data.hexString)")
            responsesReceived += 1
        }

        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicFileData) { [weak self] data in
            self?.logger.debug("Protocol", "📥 Init data on 3dda0004: \(data.count) bytes")
            responsesReceived += 1
        }

        do {
            try await bluetoothManager.write(
                data: request,
                to: FossilConstants.characteristicFileOperations,
                type: .withResponse
            )

            logger.info("Protocol", "✅ App list lookup request sent successfully")
        } catch {
            logger.warning("Protocol", "App list lookup failed: \(error.localizedDescription)")
            // Don't throw - we'll try the old FileGet method as fallback

            // Try FileGetRawRequest (0x01) for DEVICE_INFO as fallback
            logger.info("Protocol", "Trying FileGet fallback with DEVICE_INFO...")
            let deviceInfoHandle = FileHandle.deviceInfo
            var buffer = ByteBuffer(capacity: 11)
            buffer.putUInt8(0x01)  // FileGet command
            buffer.putUInt8(deviceInfoHandle.minor)
            buffer.putUInt8(deviceInfoHandle.major)
            buffer.putUInt32(0)  // Start offset
            buffer.putUInt32(0xFFFFFFFF)  // End offset (entire file)

            try await bluetoothManager.write(
                data: buffer.data,
                to: FossilConstants.characteristicFileOperations,
                type: .withResponse
            )
            logger.info("Protocol", "✅ Device info request sent successfully")
        }

        // Wait for responses to arrive
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Unregister handlers - we don't need the actual data
        bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicFileOperations)
        bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicFileData)

        if responsesReceived > 0 {
            logger.info("Protocol", "✅ File operations channel initialized (\(responsesReceived) responses)")
        } else {
            logger.warning("Protocol", "No responses received during init, continuing anyway...")
        }
    }

    /// Put a file to the watch
    /// - Parameters:
    ///   - data: The RAW file content to transfer (will be wrapped with file header)
    ///   - handle: The file handle destination
    ///   - requiresAuth: Whether this operation requires authentication (default: false)
    ///                   Notifications do NOT require auth per Gadgetbridge - they use regular FilePutRequest
    ///                   Time sync and configuration changes DO require auth - they use FileEncryptedInterface
    /// Source: FossilWatchAdapter.java - queueWrite(FossilRequest) only checks isConnected(), not authentication
    /// Source: FilePutRequest.java - createFilePayload wraps data with handle/version/offset/size/data/crc
    func putFile(_ data: Data, to handle: FileHandle, requiresAuth: Bool = false) async throws {
        guard !isTransferring else {
            throw FileTransferError.transferInProgress
        }

        if requiresAuth {
            guard authManager.isAuthenticated else {
                throw FileTransferError.notAuthenticated
            }
        }

        // CRITICAL: Wrap the raw file data with file header before sending
        // Source: FilePutRequest.java createFilePayload() adds: handle(2) + version(2) + offset(4) + size(4) + data + crc32c(4)
        // The watch expects this wrapped format when receiving file data
        let fileVersion: UInt16 = 0x0003 // TODO: Get from SupportedFileVersionsInfo
        let wrappedData = RequestBuilder.buildFilePayload(handle: handle, fileVersion: fileVersion, fileData: data)

        logger.debug("FileTransfer", "Wrapping raw data (\(data.count) bytes) → wrapped (\(wrappedData.count) bytes)")

        isTransferring = true
        progress = 0
        currentData = wrappedData
        currentHandle = handle
        bytesSent = 0
        packetIndex = 0
        fullCRC32 = wrappedData.crc32
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

        // Build and send file put header - use wrappedData for correct size
        let header = RequestBuilder.buildFilePutRequest(handle: handle, data: wrappedData)
        logger.debug("FileTransfer", "Sending PUT header for \(handle): \(header.hexString)")

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

        print("[FileTransfer] Transfer complete!")
    }

    /// Sync time to the watch
    /// Note: Time sync REQUIRES authentication per Gadgetbridge - uses FileEncryptedInterface
    /// Source: FossilHRWatchAdapter.java#L1220-L1228 - uses (FileEncryptedInterface) ConfigurationPutRequest
    func syncTime(date: Date = Date(), timeZone: TimeZone = .current) async throws {
        logger.info("TimeSync", "Starting time synchronization")

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .long
        formatter.timeZone = timeZone

        let unixTime = Int(date.timeIntervalSince1970)
        let offsetMinutes = timeZone.secondsFromGMT(for: date) / 60

        logger.debug("TimeSync", "Date: \(formatter.string(from: date))")
        logger.debug("TimeSync", "Unix timestamp: \(unixTime)")
        logger.debug("TimeSync", "Timezone: \(timeZone.identifier)")
        logger.debug("TimeSync", "Timezone offset: \(offsetMinutes) minutes (\(offsetMinutes / 60)h \(abs(offsetMinutes % 60))m)")

        let configData = RequestBuilder.buildTimeSyncRequest(date: date, timeZone: timeZone)
        logger.debug("TimeSync", "Config data: \(configData.hexString)")

        // Time sync uses the configuration file handle - requires authentication
        try await putFile(configData, to: .configuration, requiresAuth: true)

        logger.info("TimeSync", "✅ Time synced successfully to \(formatter.string(from: date))")
    }

    /// Install a watch app (.wapp file)
    func installApp(wappData: Data) async throws {
        // The .wapp format already includes the file handle header
        // We just need to send it to the APP_CODE handle
        try await putFile(wappData, to: .appCode)

        print("[FileTransfer] App installed (\(wappData.count) bytes)")
    }

    /// Fetch an encrypted file from the watch
    /// - Parameter handle: The file handle to fetch
    /// - Returns: The decrypted file data
    func fetchEncryptedFile(for handle: FileHandle) async throws -> Data {
        // Use the encrypted file reader to fetch the file
        guard !isOperationInProgress else {
            logger.warning("FileTransfer", "Another file operation is already in progress")
            throw FileTransferError.transferInProgress
        }

        isOperationInProgress = true
        defer { isOperationInProgress = false }

        return try await encryptedFileReader.fetchEncryptedFile(for: handle)
    }

    /// Read battery information from the configuration file
    /// Source: ConfigurationGetRequest.java#L20-L73 and BatteryConfigItem
    func readBatteryStatus() async throws -> BatteryStatus {
        logger.info("Battery", "Requesting battery status from watch")

        // Use the fetchEncryptedFile method which handles the operation lock
        let fileData = try await fetchEncryptedFile(for: .configuration)
        logger.debug("Battery", "Received configuration file: \(fileData.count) bytes")
        logger.debug("Battery", "Full file (hex): \(fileData.hexString)")

        guard fileData.count > 16 else {
            throw FileTransferError.invalidResponse
        }

        // Source: fossil_hr/configuration/ConfigurationGetRequest.java#L40-42
        // Skip first 12 bytes (header) and last 4 bytes (CRC/trailer)
        let payloadRange = 12..<(fileData.count - 4)
        let payload = fileData.subdata(in: payloadRange)
        logger.debug("Battery", "Payload (after header/trailer strip): \(payload.count) bytes")
        logger.debug("Battery", "Payload (hex): \(payload.hexString)")

        var buffer = ByteBuffer(data: payload)
        var status: BatteryStatus?
        var itemCount = 0

        while buffer.remainingBytes > 0 {
            guard let rawId = buffer.getUInt16(),
                  let lengthByte = buffer.getUInt8() else {
                logger.warning("Battery", "Couldn't read item header at offset \(itemCount)")
                break
            }

            let length = Int(lengthByte)
            itemCount += 1

            logger.debug("Battery", "Item \(itemCount): ID=0x\(String(format: "%04X", rawId)), length=\(length)")

            guard let bytes = buffer.getBytes(length) else {
                logger.warning("Battery", "Couldn't read \(length) bytes for item 0x\(String(format: "%04X", rawId))")
                break
            }

            // Battery config item ID is 0x0D
            if rawId == 0x0D {
                logger.info("Battery", "Found battery config item!")
                logger.debug("Battery", "Battery bytes: \(Data(bytes).hexString)")
                // Gadgetbridge expects 3 bytes, but some watches send 4 (extra state byte)
                guard bytes.count >= 3 else {
                    logger.warning("Battery", "Battery data too short: \(bytes.count) bytes (need at least 3)")
                    continue
                }

                let voltage = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                let percentage = Int(bytes[2])
                status = BatteryStatus(percentage: percentage, voltageMillivolts: Int(voltage))
                logger.info("Battery", "Battery: \(percentage)% at \(voltage) mV")
                if bytes.count > 3 {
                    logger.debug("Battery", "Extra battery byte: 0x\(String(format: "%02X", bytes[3])) (state?)")
                }
                break
            }
        }

        guard let result = status else {
            logger.warning("Battery", "Battery config item (0x0D) not found in \(itemCount) items")
            throw FileTransferError.batteryConfigMissing
        }

        logger.info("Battery", "Battery level \(result.percentage)% (\(result.voltageMillivolts) mV)")
        return result
    }

    // MARK: - Private Methods - File Put

    private func handleFileResponse(_ data: Data) {
        guard data.count >= 1 else { return }

        let responseType = data[0] & 0x0F

        print("[FileTransfer] Response type: \(String(format: "0x%02X", responseType)), data: \(data.hexString)")

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
            print("[FileTransfer] Unknown response type: \(responseType)")
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
                print("[FileTransfer] PUT init failed: \(code)")
            }
            failTransfer(with: .rejected(resultCode))
            return
        }

        print("[FileTransfer] PUT init accepted, starting data transfer")
        transferState = .sendingData
        continueDataTransfer()
    }

    private func handleDataAck(_ data: Data) {
        if data.count == 4 {
            continueDataTransfer()
            return
        }

        guard data.count >= 12 else {
            failTransfer(with: .invalidResponse)
            return
        }

        let handleValue = UInt16(data[1]) | (UInt16(data[2]) << 8)
        let status = data[3]
        let receivedCRC = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian

        guard status == 0 else {
            failTransfer(with: .rejected(status))
            return
        }

        if handleValue != currentHandle?.rawValue {
            failTransfer(with: .invalidResponse)
            return
        }

        if receivedCRC != fullCRC32 {
            failTransfer(with: .invalidResponse)
            return
        }

        continueDataTransfer()
    }

    private func handleTransferComplete(_ data: Data) {
        guard data.count >= 4 else {
            failTransfer(with: .invalidResponse)
            return
        }

        let resultCode = data[3]
        // Result codes:
        // 0x00 = Success
        // 0x05 = File written/applied (seen for notification filters, icons, and notifications)
        // Other codes may be actual errors
        // Source: Based on observed behavior with Skagen Gen 6 Hybrid
        if resultCode == 0 || resultCode == 0x05 {
            if resultCode == 0x05 {
                print("[FileTransfer] Transfer complete with code 0x05 (file written/applied)")
            }
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
            sendCloseCommand()
            return
        }

        // Calculate chunk size
        let chunkSize = min(remaining, mtuSize - 1)  // -1 for packet header

        // Build data packet
        var packet = Data(capacity: chunkSize + 1)
        packet.append(packetIndex)
        packet.append(data.subdata(in: bytesSent..<(bytesSent + chunkSize)))

        packetIndex &+= 1
        bytesSent += chunkSize
        progress = Double(bytesSent) / Double(data.count)

        print("[FileTransfer] Sending chunk: \(bytesSent)/\(data.count) bytes (\(Int(progress * 100))%)")

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

    private func sendCloseCommand() {
        guard let handle = currentHandle else { return }
        var buffer = ByteBuffer(capacity: 3)
        buffer.putUInt8(FossilConstants.Command.fileClose.rawValue)
        buffer.putUInt16(handle.rawValue)

        Task {
            do {
                try await bluetoothManager.write(
                    data: buffer.data,
                    to: FossilConstants.characteristicFileOperations
                )
            } catch {
                failTransfer(with: .writeFailed(error))
            }
        }
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
    case missingEncryptionContext
    case invalidCRC
    case emptyFile
    case unexpectedHandle
    case invalidDecryption
    case batteryConfigMissing

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
        case .missingEncryptionContext:
            return "Missing encryption context (secret key or random numbers)"
        case .invalidCRC:
            return "CRC mismatch while validating file data"
        case .emptyFile:
            return "File is empty"
        case .unexpectedHandle:
            return "Received data for unexpected file handle"
        case .invalidDecryption:
            return "Could not decrypt file payload"
        case .batteryConfigMissing:
            return "Battery configuration item not present in configuration file"
        }
    }
}
