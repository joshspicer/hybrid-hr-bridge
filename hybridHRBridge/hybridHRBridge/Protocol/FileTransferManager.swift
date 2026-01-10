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

    private struct EncryptedReadState {
        enum Phase {
            case lookup
            case encryptedGet
        }

        var phase: Phase = .lookup
        var dynamicHandle: UInt16?
        var lookupExpectedSize: Int = 0
        var lookupBuffer = Data()
        var fileSize: Int = 0
        var fileBuffer = Data()
        let originalIV: Data
        let key: Data
        var packetCount: Int = 0
        var ivIncrementor: Int = 0x1F
    }
    
    // MARK: - Private Properties
    
    private let bluetoothManager: BluetoothManager
    private let authManager: AuthenticationManager
    private let logger = LogManager.shared
    
    /// Semaphore to ensure only one file operation at a time
    private let operationSemaphore = DispatchSemaphore(value: 1)
    /// Flag to track if an operation is in progress
    @Published private(set) var isOperationInProgress = false

    private var transferState: TransferState = .idle
    private var currentData: Data?
    private var currentHandle: FileHandle?
    private var bytesSent: Int = 0
    private var packetIndex: UInt8 = 0
    private var fullCRC32: UInt32 = 0
    private var transferContinuation: CheckedContinuation<Void, Error>?
    private var readState: EncryptedReadState?
    private var readContinuation: CheckedContinuation<Data, Error>?
    private var readTimeoutTask: Task<Void, Never>?

    // MTU for data packets (iOS typically negotiates 185-517)
    // Leave room for BLE overhead
    private var mtuSize: Int = 180
    
    // MARK: - Initialization
    
    init(bluetoothManager: BluetoothManager, authManager: AuthenticationManager) {
        self.bluetoothManager = bluetoothManager
        self.authManager = authManager
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
    ///   - data: The file data to transfer
    ///   - handle: The file handle destination
    ///   - requiresAuth: Whether this operation requires authentication (default: false)
    ///                   Notifications do NOT require auth per Gadgetbridge - they use regular FilePutRequest
    ///                   Time sync and configuration changes DO require auth - they use FileEncryptedInterface
    /// Source: FossilWatchAdapter.java - queueWrite(FossilRequest) only checks isConnected(), not authentication
    func putFile(_ data: Data, to handle: FileHandle, requiresAuth: Bool = false) async throws {
        guard !isTransferring else {
            throw FileTransferError.transferInProgress
        }
        
        if requiresAuth {
            guard authManager.isAuthenticated else {
                throw FileTransferError.notAuthenticated
            }
        }
        
        isTransferring = true
        progress = 0
        currentData = data
        currentHandle = handle
        bytesSent = 0
        packetIndex = 0
        fullCRC32 = data.crc32
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
        print("[FileTransfer] Sending PUT header for \(handle): \(header.hexString)")
        
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
    
    /// Send a notification to the watch
    /// Note: Notifications do NOT require authentication per Gadgetbridge
    /// Source: FossilHRWatchAdapter.java#L1388-L1433 - playRawNotification uses PlayTextNotificationRequest
    ///         which extends FilePutRequest (not FileEncryptedInterface)
    func sendNotification(
        type: NotificationType,
        title: String,
        sender: String,
        message: String,
        appIdentifier: String
    ) async throws {
        let messageID = UInt32.random(in: 0...UInt32.max)
        let packageCRC = appIdentifier.crc32

        logger.info("Notification", "Sending notification to watch (no auth required)")
        logger.debug("Notification", "Type: \(type), ID: \(messageID)")
        logger.debug("Notification", "Title: '\(title)'")
        logger.debug("Notification", "Sender: '\(sender)'")
        logger.debug("Notification", "Message: '\(message.prefix(100))\(message.count > 100 ? "..." : "")'")
        logger.debug("Notification", "App: \(appIdentifier), CRC32: 0x\(String(format: "%08X", packageCRC))")

        let payload = RequestBuilder.buildNotification(
            type: type,
            title: title,
            sender: sender,
            message: message,
            packageCRC: packageCRC,
            messageID: messageID
        )

        logger.debug("Notification", "Payload size: \(payload.count) bytes")
        logger.debug("Notification", "Payload data: \(payload.prefix(20).hexString)...")

        // Notifications don't require authentication - only BLE connection
        try await putFile(payload, to: .notificationPlay, requiresAuth: false)

        logger.info("Notification", "✅ Notification sent successfully (ID: \(messageID))")
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

    /// Read battery information from the configuration file
    /// Source: ConfigurationGetRequest.java#L20-L73 and BatteryConfigItem
    func readBatteryStatus() async throws -> BatteryStatus {
        logger.info("Battery", "Requesting battery status from watch")

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
    
    // MARK: - Private Methods
    
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

    // MARK: - Encrypted File Read

    /// Fetch an encrypted file from the watch (public API for other managers)
    /// This performs a file lookup followed by an encrypted get request
    /// Source: FossilHRWatchAdapter.java#L1166-1182 - queueWrite(FileEncryptedInterface) calls VerifyPrivateKeyRequest first
    /// CRITICAL: In Gadgetbridge, VerifyPrivateKeyRequest is called IMMEDIATELY before each encrypted file operation
    /// The auth must complete, then the file operation starts right after without any other requests in between
    func fetchEncryptedFile(for handle: FileHandle) async throws -> Data {
        logger.info("Protocol", "=== Starting encrypted file fetch for \(handle) ===")
        
        guard authManager.isAuthenticated else {
            logger.error("Protocol", "Not authenticated, cannot fetch encrypted file")
            throw FileTransferError.notAuthenticated
        }

        // Try to acquire the semaphore (non-blocking check first)
        guard !isOperationInProgress else {
            logger.warning("Protocol", "Another file operation is already in progress")
            throw FileTransferError.transferInProgress
        }
        
        isOperationInProgress = true
        defer { 
            isOperationInProgress = false
            logger.debug("Protocol", "Operation complete, releasing lock")
        }
        
        // CRITICAL: Do VerifyPrivateKeyRequest (re-auth) IMMEDIATELY before the encrypted file operation
        // This is exactly how Gadgetbridge does it - the auth generates fresh randoms that are used for encryption
        // Source: FossilHRWatchAdapter.java queueWrite(FileEncryptedInterface) - always does VerifyPrivateKeyRequest first
        logger.info("Protocol", "Refreshing authentication (VerifyPrivateKeyRequest) for fresh randoms...")
        try await authManager.verifyAuthentication()
        
        guard let key = authManager.getSecretKey(),
              let phoneRandom = authManager.getPhoneRandomNumber(),
              let watchRandom = authManager.getWatchRandomNumber() else {
            logger.error("Protocol", "Missing encryption context after verify")
            throw FileTransferError.missingEncryptionContext
        }

        logger.debug("Protocol", "Key available: \(key.count) bytes")
        logger.debug("Protocol", "Phone random: \(phoneRandom.hexString)")
        logger.debug("Protocol", "Watch random: \(watchRandom.hexString)")

        let iv = AESCrypto.generateFileIV(phoneRandom: phoneRandom, watchRandom: watchRandom)
        logger.debug("Protocol", "Generated IV: \(iv.hexString)")
        
        readState = EncryptedReadState(
            dynamicHandle: nil,
            lookupExpectedSize: 0,
            lookupBuffer: Data(),
            fileSize: 0,
            fileBuffer: Data(),
            originalIV: iv,
            key: key,
            packetCount: 0,
            ivIncrementor: 0x1F
        )

        logger.debug("Protocol", "Registering notification handlers...")
        
        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicFileOperations) { [weak self] data in
            Task { @MainActor in
                self?.logger.debug("Protocol", "📥 Received on 3dda0003: \(data.hexString)")
                self?.handleEncryptedReadResponse(data)
            }
        }

        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicFileData) { [weak self] data in
            Task { @MainActor in
                self?.logger.debug("Protocol", "📥 Received on 3dda0004: \(data.count) bytes (first: 0x\(String(format: "%02X", data.first ?? 0)))")
                self?.handleEncryptedReadData(data)
            }
        }
        
        // Note: Notifications were already enabled during connection setup
        // Don't call enableNotifications again - that can cause issues with the BLE stack
        logger.debug("Protocol", "Using existing notification handlers...")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            self.readContinuation = continuation

            self.readTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await MainActor.run {
                    if self?.readState != nil {
                        self?.logger.error("Protocol", "⏰ Timeout waiting for file data")
                        self?.failRead(with: .timeout)
                    }
                }
            }

            Task { [weak self] in
                guard let self = self else { return }

                do {
                    // Use FileLookupRequest for all handles
                    // After pairing, the watch should allow encrypted file access
                    // Source: FileEncryptedLookupAndGetRequest.java - always does lookup first
                    let request = RequestBuilder.buildFileLookupRequest(for: handle)
                    self.logger.info("Protocol", "📤 Sending lookup request: \(request.hexString)")
                    try await self.bluetoothManager.write(
                        data: request,
                        to: FossilConstants.characteristicFileOperations,
                        type: .withResponse
                    )
                    self.logger.info("Protocol", "✅ Lookup request sent successfully")
                } catch {
                    self.logger.error("Protocol", "❌ Write failed: \(error.localizedDescription)")
                    await MainActor.run {
                        self.failRead(with: .writeFailed(error))
                    }
                }
            }
        }
    }

    private func handleEncryptedReadResponse(_ data: Data) {
        guard var state = readState, !data.isEmpty else { 
            logger.warning("Protocol", "handleEncryptedReadResponse: No read state or empty data")
            return 
        }

        let responseType = data[0] & 0x0F
        logger.debug("Protocol", "Response type: 0x\(String(format: "%02X", responseType)), phase: \(state.phase)")

        do {
            switch state.phase {
            case .lookup:
                if let resolvedHandle = try handleLookupResponse(data, responseType: responseType, state: &state) {
                    readState = state
                    let major = UInt8((resolvedHandle >> 8) & 0xFF)
                    let minor = UInt8(resolvedHandle & 0xFF)
                    logger.info("Protocol", "Lookup complete! Resolved to major=0x\(String(format: "%02X", major)), minor=0x\(String(format: "%02X", minor))")
                    sendEncryptedGetRequest(major: major, minor: minor)
                    return
                }
            case .encryptedGet:
                let shouldComplete = try handleEncryptedGetControl(data, responseType: responseType, state: &state)
                readState = state
                if shouldComplete {
                    logger.info("Protocol", "Encrypted get complete, \(state.fileBuffer.count) bytes received")
                    completeRead(with: state.fileBuffer)
                }
                return
            }
        } catch let error as FileTransferError {
            logger.error("Protocol", "Response handling error: \(error.localizedDescription)")
            failRead(with: error)
            return
        } catch {
            logger.error("Protocol", "Unexpected error: \(error)")
            failRead(with: .invalidResponse)
            return
        }

        readState = state
    }

    private func handleEncryptedReadData(_ data: Data) {
        guard var state = readState, !data.isEmpty else { 
            logger.warning("Protocol", "handleEncryptedReadData: No read state or empty data")
            return 
        }

        switch state.phase {
        case .lookup:
            logger.debug("Protocol", "Lookup data received: \(data.count) bytes, buffer now: \(state.lookupBuffer.count + data.count - 1) bytes")
            if data.count > 1 {
                state.lookupBuffer.append(data.dropFirst())
            }
            if state.lookupExpectedSize > 0, state.lookupBuffer.count > state.lookupExpectedSize {
                logger.error("Protocol", "Lookup buffer overflow: \(state.lookupBuffer.count) > \(state.lookupExpectedSize)")
                failRead(with: .invalidResponse)
                return
            }
        case .encryptedGet:
            do {
                try decryptEncryptedPacket(data, state: &state)
                logger.debug("Protocol", "Decrypted packet \(state.packetCount - 1), buffer now: \(state.fileBuffer.count) bytes")
            } catch let error as FileTransferError {
                logger.error("Protocol", "Decrypt error: \(error.localizedDescription)")
                failRead(with: error)
                return
            } catch {
                logger.error("Protocol", "Unexpected decrypt error: \(error)")
                failRead(with: .invalidResponse)
                return
            }
        }

        readState = state
    }

    private func handleLookupResponse(_ data: Data, responseType: UInt8, state: inout EncryptedReadState) throws -> UInt16? {
        switch responseType {
        case 0x02:
            guard data.count >= 8 else {
                throw FileTransferError.invalidResponse
            }

            let status = data[3]
            guard status == 0 else {
                throw FileTransferError.rejected(status)
            }

            let size = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
            guard size > 0 else {
                throw FileTransferError.emptyFile
            }

            state.lookupExpectedSize = Int(size)
            state.lookupBuffer.reserveCapacity(Int(size))
            logger.debug("Protocol", "Lookup expects \(size) bytes")
            return nil

        case 0x08:
            guard data.count >= 12 else {
                throw FileTransferError.invalidResponse
            }

            let status = data[3]
            guard status == 0 else {
                throw FileTransferError.rejected(status)
            }

            let expectedCRC = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
            let computedCRC = state.lookupBuffer.crc32

            guard expectedCRC == computedCRC else {
                throw FileTransferError.invalidCRC
            }

            guard state.lookupBuffer.count >= 2 else {
                throw FileTransferError.invalidResponse
            }

            var buffer = ByteBuffer(data: state.lookupBuffer)
            guard let handleValue = buffer.getUInt16() else {
                throw FileTransferError.invalidResponse
            }

            state.dynamicHandle = handleValue
            state.phase = .encryptedGet
            state.packetCount = 0
            state.ivIncrementor = 0x1F
            state.fileBuffer.removeAll(keepingCapacity: true)
            state.lookupBuffer.removeAll(keepingCapacity: false)

            logger.info("Protocol", "Lookup resolved handle 0x\(String(format: "%04X", handleValue))")
            return handleValue

        default:
            return nil
        }
    }

    private func handleEncryptedGetControl(_ data: Data, responseType: UInt8, state: inout EncryptedReadState) throws -> Bool {
        switch responseType {
        case FossilConstants.ResponseType.fileGetInit.rawValue:
            guard data.count >= 8 else {
                throw FileTransferError.invalidResponse
            }

            let status = data[3]
            guard status == 0 else {
                throw FileTransferError.rejected(status)
            }

            let minor = data[1]
            let major = data[2]

            if let expected = state.dynamicHandle {
                let expectedMinor = UInt8(expected & 0xFF)
                let expectedMajor = UInt8((expected >> 8) & 0xFF)
                guard expectedMinor == minor, expectedMajor == major else {
                    throw FileTransferError.unexpectedHandle
                }
            }

            let fileSize = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
            state.fileSize = Int(fileSize)
            state.fileBuffer.removeAll(keepingCapacity: true)
            state.fileBuffer.reserveCapacity(Int(fileSize))
            state.packetCount = 0

            logger.info("Protocol", "Encrypted file transfer size: \(fileSize) bytes")
            return false

        case 0x08:
            guard data.count >= 12 else {
                throw FileTransferError.invalidResponse
            }

            let status = data[3]
            guard status == 0 else {
                throw FileTransferError.rejected(status)
            }

            let expectedCRC = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
            let actualCRC = state.fileBuffer.crc32
            
            logger.debug("Protocol", "CRC validation: expected=0x\(String(format: "%08X", expectedCRC)), actual=0x\(String(format: "%08X", actualCRC))")
            logger.debug("Protocol", "File buffer size: \(state.fileBuffer.count) bytes, expected: \(state.fileSize) bytes")
            
            if state.fileBuffer.count > 0 {
                let firstBytes = state.fileBuffer.prefix(min(16, state.fileBuffer.count))
                logger.debug("Protocol", "File buffer first bytes: \(firstBytes.hexString)")
            }

            guard expectedCRC == actualCRC else {
                logger.error("Protocol", "CRC mismatch! Expected: 0x\(String(format: "%08X", expectedCRC)), Got: 0x\(String(format: "%08X", actualCRC))")
                throw FileTransferError.invalidCRC
            }

            return true

        default:
            return false
        }
    }

    private func decryptEncryptedPacket(_ packet: Data, state: inout EncryptedReadState) throws {
        logger.debug("Protocol", "Decrypting packet \(state.packetCount): \(packet.count) bytes")
        logger.debug("Protocol", "Packet header: 0x\(String(format: "%02X", packet.first ?? 0))")
        
        let decrypted: Data

        if state.packetCount == 0 {
            logger.debug("Protocol", "Using original IV for first packet")
            decrypted = try AESCrypto.cryptCTR(data: packet, key: state.key, iv: state.originalIV)
        } else if state.packetCount == 1 {
            var resolved: Data?

            for summand in 0x1E...0x2F {
                let iv = AESCrypto.incrementedIV(from: state.originalIV, by: Int(summand))
                let candidate = try AESCrypto.cryptCTR(data: packet, key: state.key, iv: iv)
                guard let header = candidate.first else { continue }

                let projectedLength = state.fileBuffer.count + max(candidate.count - 1, 0)
                let expectedHeader: UInt8 = projectedLength == state.fileSize ? 0x81 : 0x01

                if header == expectedHeader {
                    state.ivIncrementor = Int(summand)
                    resolved = candidate
                    logger.debug("Protocol", "Resolved IV increment: 0x\(String(format: "%02X", summand))")
                    break
                }
            }

            guard let successful = resolved else {
                throw FileTransferError.invalidDecryption
            }

            decrypted = successful
        } else {
            let incrementAmount = state.ivIncrementor * state.packetCount
            let iv = AESCrypto.incrementedIV(from: state.originalIV, by: incrementAmount)
            logger.debug("Protocol", "Using IV increment \(incrementAmount) for packet \(state.packetCount)")
            decrypted = try AESCrypto.cryptCTR(data: packet, key: state.key, iv: iv)
        }

        state.packetCount += 1

        guard let header = decrypted.first else {
            throw FileTransferError.invalidResponse
        }
        
        logger.debug("Protocol", "Decrypted header: 0x\(String(format: "%02X", header)), payload size: \(decrypted.count - 1)")

        let payload = decrypted.dropFirst()
        state.fileBuffer.append(payload)

        if header & 0x80 == 0x80 {
            logger.debug("Protocol", "Last encrypted packet received (\(state.fileBuffer.count) bytes)")
        }
    }

    private func sendEncryptedGetRequest(major: UInt8, minor: UInt8) {
        Task { [weak self] in
            guard let self = self else { return }

            // Small delay before sending get request
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            do {
                let request = RequestBuilder.buildFileGetRequest(major: major, minor: minor)
                self.logger.debug("Protocol", "Encrypted get request: \(request.hexString)")
                // Use withResponse for encrypted get requests to ensure reliable delivery
                try await self.bluetoothManager.write(
                    data: request,
                    to: FossilConstants.characteristicFileOperations,
                    type: .withResponse
                )
                self.logger.info("Protocol", "Encrypted get request sent (major: 0x\(String(format: "%02X", major)), minor: 0x\(String(format: "%02X", minor)))")
            } catch {
                await MainActor.run {
                    self.failRead(with: .writeFailed(error))
                }
            }
        }
    }

    private func cleanupReadHandlers() {
        bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicFileOperations)
        bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicFileData)
        readTimeoutTask?.cancel()
        readTimeoutTask = nil
    }

    private func failRead(with error: FileTransferError) {
        guard readState != nil else { return }

        logger.error("Protocol", "Encrypted read failed: \(error.localizedDescription)")
        lastError = error
        readState = nil
        cleanupReadHandlers()

        if let continuation = readContinuation {
            readContinuation = nil
            continuation.resume(throwing: error)
        }
    }

    private func completeRead(with data: Data) {
        logger.info("Protocol", "Encrypted read completed (\(data.count) bytes)")
        cleanupReadHandlers()
        readState = nil

        if let continuation = readContinuation {
            readContinuation = nil
            continuation.resume(returning: data)
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
