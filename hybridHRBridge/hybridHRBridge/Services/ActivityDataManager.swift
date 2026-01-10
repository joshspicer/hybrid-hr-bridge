import Foundation
import Combine

/// Manages fetching and parsing activity data from the watch
/// Handles the multi-step process: file lookup → encrypted file get → parse
///
/// Source: FossilHRWatchAdapter.java#L1279-L1339
/// https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil_hr/FossilHRWatchAdapter.java
@MainActor
final class ActivityDataManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isFetching = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastFetchedData: ActivityData?
    @Published private(set) var lastError: ActivityFetchError?
    
    // MARK: - Private Properties
    
    private let bluetoothManager: BluetoothManager
    private let authManager: AuthenticationManager
    private let logger = LogManager.shared
    private let parser = ActivityFileParser()
    
    // File transfer state
    private var fileBuffer: Data?
    private var expectedFileSize: Int = 0
    private var fetchContinuation: CheckedContinuation<Data, Error>?
    
    // Encryption state
    private var cipher: ((Data, Data) throws -> Data)?
    private var originalIV: Data?
    private var ivIncrementor: Int = 0x1F
    private var packetCount: Int = 0
    
    // MARK: - Initialization
    
    init(bluetoothManager: BluetoothManager, authManager: AuthenticationManager) {
        self.bluetoothManager = bluetoothManager
        self.authManager = authManager
    }
    
    // MARK: - Public API
    
    /// Fetch activity data from the watch
    /// This performs a multi-step process:
    /// 1. Send file lookup request to get the dynamic file handle
    /// 2. Send encrypted file get request
    /// 3. Receive and decrypt the file data
    /// 4. Parse the activity file
    ///
    /// - Returns: Parsed activity data containing steps, heart rate, calories, etc.
    func fetchActivityData() async throws -> ActivityData {
        guard !isFetching else {
            throw ActivityFetchError.fetchInProgress
        }
        
        guard authManager.isAuthenticated else {
            logger.error("Activity", "Cannot fetch activity data - not authenticated")
            throw ActivityFetchError.notAuthenticated
        }
        
        isFetching = true
        progress = 0
        lastError = nil
        
        defer {
            isFetching = false
            progress = 0
            resetState()
        }
        
        logger.info("Activity", "Starting activity data fetch")
        
        do {
            // Step 1: Look up the activity file handle
            logger.info("Activity", "Step 1: Looking up activity file handle")
            let fileHandle = try await lookupFileHandle(for: .activityFile)
            logger.info("Activity", "Got activity file handle: 0x\(String(format: "%04X", fileHandle))")
            progress = 0.1
            
            // Step 2: Fetch the encrypted file
            logger.info("Activity", "Step 2: Fetching encrypted activity file")
            let encryptedData = try await fetchEncryptedFile(handle: fileHandle)
            logger.info("Activity", "Received \(encryptedData.count) bytes of activity data")
            progress = 0.8
            
            // Step 3: Parse the activity data
            logger.info("Activity", "Step 3: Parsing activity data")
            let activityData = try parser.parseFile(encryptedData)
            progress = 1.0
            
            lastFetchedData = activityData
            logger.info("Activity", "✅ Activity fetch complete - \(activityData.samples.count) samples, \(activityData.totalSteps) total steps")
            
            return activityData
            
        } catch {
            logger.error("Activity", "Activity fetch failed: \(error.localizedDescription)")
            let fetchError = error as? ActivityFetchError ?? .fetchFailed(error)
            lastError = fetchError
            throw fetchError
        }
    }
    
    // MARK: - File Lookup
    
    /// Look up the actual file handle for a file type
    /// Source: FileLookupRequest.java
    private func lookupFileHandle(for handle: FileHandle) async throws -> UInt16 {
        logger.debug("Activity", "Looking up file handle for \(handle)")
        
        // Build lookup request
        let request = RequestBuilder.buildFileLookupRequest(for: handle)
        logger.debug("Activity", "Lookup request: \(request.hexString)")
        
        // Register handler for response
        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicFileOperations) { [weak self] data in
            Task { @MainActor in
                self?.handleLookupResponse(data)
            }
        }
        
        // Also need to register for data characteristic
        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicFileData) { [weak self] data in
            Task { @MainActor in
                self?.handleLookupData(data)
            }
        }
        
        // Enable notifications
        try await bluetoothManager.enableNotifications(for: FossilConstants.characteristicFileOperations)
        try await bluetoothManager.enableNotifications(for: FossilConstants.characteristicFileData)
        
        // Reset state for lookup
        fileBuffer = nil
        expectedFileSize = 0
        
        // Send lookup request
        try await bluetoothManager.write(
            data: request,
            to: FossilConstants.characteristicFileOperations
        )
        
        // Wait for response with timeout
        let lookupData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            self.fetchContinuation = continuation
            
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                if self.fileBuffer == nil {
                    self.fetchContinuation?.resume(throwing: ActivityFetchError.timeout)
                    self.fetchContinuation = nil
                }
            }
        }
        
        // Parse handle from lookup response (first 2 bytes)
        guard lookupData.count >= 2 else {
            throw ActivityFetchError.invalidResponse
        }
        
        let resolvedHandle = UInt16(lookupData[0]) | (UInt16(lookupData[1]) << 8)
        return resolvedHandle
    }
    
    /// Handle file lookup response on operations characteristic
    /// Source: FileLookupRequest.java#L63-L90
    private func handleLookupResponse(_ data: Data) {
        logger.debug("Activity", "Lookup response: \(data.hexString)")
        
        guard data.count >= 1 else { return }
        let responseType = data[0] & 0x0F
        
        if responseType == 0x02 {
            // File lookup init response
            guard data.count >= 8 else {
                logger.error("Activity", "Lookup response too short")
                return
            }
            
            // Check status
            let status = data[3]
            if status != 0 {
                logger.error("Activity", "Lookup failed with status: \(status)")
                fetchContinuation?.resume(throwing: ActivityFetchError.lookupFailed(status))
                fetchContinuation = nil
                return
            }
            
            // Get file size
            let size = Int(data[4]) |
                      (Int(data[5]) << 8) |
                      (Int(data[6]) << 16) |
                      (Int(data[7]) << 24)
            
            logger.debug("Activity", "Lookup response - size: \(size)")
            
            if size == 0 {
                logger.warning("Activity", "Activity file is empty")
                fetchContinuation?.resume(throwing: ActivityFetchError.fileEmpty)
                fetchContinuation = nil
                return
            }
            
            expectedFileSize = size
            fileBuffer = Data(capacity: size)
            
        } else if responseType == 0x08 {
            // File complete
            guard data.count >= 12 else { return }
            
            // Verify CRC
            let expectedCRC = UInt32(data[8]) |
                             (UInt32(data[9]) << 8) |
                             (UInt32(data[10]) << 16) |
                             (UInt32(data[11]) << 24)
            
            guard let buffer = fileBuffer else { return }
            let actualCRC = buffer.crc32
            
            if actualCRC != expectedCRC {
                logger.error("Activity", "CRC mismatch - expected: \(expectedCRC), got: \(actualCRC)")
                fetchContinuation?.resume(throwing: ActivityFetchError.crcMismatch)
                fetchContinuation = nil
                return
            }
            
            logger.debug("Activity", "Lookup complete, CRC verified")
            fetchContinuation?.resume(returning: buffer)
            fetchContinuation = nil
        }
    }
    
    /// Handle file lookup data on data characteristic
    private func handleLookupData(_ data: Data) {
        guard data.count > 1 else { return }
        
        let first = data[0]
        // Append data (skip first byte which is packet index)
        fileBuffer?.append(data.subdata(in: 1..<data.count))
        
        // Check if this is the last packet (high bit set)
        if (first & 0x80) == 0x80 {
            logger.debug("Activity", "Lookup data complete - \(fileBuffer?.count ?? 0) bytes")
        }
    }
    
    // MARK: - Encrypted File Get
    
    /// Fetch an encrypted file from the watch
    /// Source: FileEncryptedGetRequest.java
    private func fetchEncryptedFile(handle: UInt16) async throws -> Data {
        logger.debug("Activity", "Fetching encrypted file with handle: 0x\(String(format: "%04X", handle))")
        
        // Initialize encryption
        try initDecryption()
        
        // Build get request
        let major = UInt8((handle >> 8) & 0xFF)
        let minor = UInt8(handle & 0xFF)
        let request = RequestBuilder.buildFileGetRequest(major: major, minor: minor)
        logger.debug("Activity", "File get request: \(request.hexString)")
        
        // Register handlers
        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicFileOperations) { [weak self] data in
            Task { @MainActor in
                self?.handleEncryptedGetResponse(data)
            }
        }
        
        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicFileData) { [weak self] data in
            Task { @MainActor in
                self?.handleEncryptedData(data)
            }
        }
        
        // Reset state
        fileBuffer = nil
        expectedFileSize = 0
        packetCount = 0
        
        // Send request
        try await bluetoothManager.write(
            data: request,
            to: FossilConstants.characteristicFileOperations
        )
        
        // Wait for completion
        let fileData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            self.fetchContinuation = continuation
            
            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds for large files
                if self.fileBuffer != nil && self.fetchContinuation != nil {
                    self.logger.error("Activity", "File fetch timed out")
                    self.fetchContinuation?.resume(throwing: ActivityFetchError.timeout)
                    self.fetchContinuation = nil
                }
            }
        }
        
        return fileData
    }
    
    /// Initialize decryption for encrypted file transfer
    /// Source: FileEncryptedGetRequest.java#L60-L77
    private func initDecryption() throws {
        guard let phoneRandom = authManager.getPhoneRandomNumber(),
              let watchRandom = authManager.getWatchRandomNumber(),
              let secretKey = authManager.getSecretKey() else {
            throw ActivityFetchError.encryptionNotReady
        }
        
        // Build initial IV
        // Source: FileEncryptedGetRequest.java#L67-L77
        originalIV = AESCrypto.generateFileIV(phoneRandom: phoneRandom, watchRandom: watchRandom)
        logger.debug("Activity", "Initial IV: \(originalIV!.hexString)")
        
        // Store decryption function
        cipher = { data, iv in
            try AESCrypto.cryptCTR(data: data, key: secretKey, iv: iv)
        }
        
        packetCount = 0
        ivIncrementor = 0x1F // Default incrementor, will be determined from first packet
    }
    
    /// Handle encrypted file get response
    /// Source: FileEncryptedGetRequest.java#L101-L142
    private func handleEncryptedGetResponse(_ data: Data) {
        logger.debug("Activity", "Get response: \(data.hexString)")
        
        guard data.count >= 1 else { return }
        let responseType = data[0] & 0x0F
        
        if responseType == 0x01 {
            // File get init response
            guard data.count >= 8 else {
                logger.error("Activity", "Get response too short")
                return
            }
            
            // Check status
            let status = data[3]
            if status != 0 {
                logger.error("Activity", "File get failed with status: \(status)")
                fetchContinuation?.resume(throwing: ActivityFetchError.getFailed(status))
                fetchContinuation = nil
                return
            }
            
            // Get file size
            let size = Int(data[4]) |
                      (Int(data[5]) << 8) |
                      (Int(data[6]) << 16) |
                      (Int(data[7]) << 24)
            
            logger.debug("Activity", "File size: \(size)")
            expectedFileSize = size
            fileBuffer = Data(capacity: size)
            
        } else if responseType == 0x08 {
            // File complete
            guard data.count >= 12, let buffer = fileBuffer else { return }
            
            // Verify CRC
            let expectedCRC = UInt32(data[8]) |
                             (UInt32(data[9]) << 8) |
                             (UInt32(data[10]) << 16) |
                             (UInt32(data[11]) << 24)
            
            let actualCRC = buffer.crc32
            
            if actualCRC != expectedCRC {
                logger.error("Activity", "CRC mismatch - expected: \(expectedCRC), got: \(actualCRC)")
                fetchContinuation?.resume(throwing: ActivityFetchError.crcMismatch)
                fetchContinuation = nil
                return
            }
            
            logger.info("Activity", "File transfer complete, CRC verified (\(buffer.count) bytes)")
            fetchContinuation?.resume(returning: buffer)
            fetchContinuation = nil
        }
    }
    
    /// Handle encrypted data packets
    /// Source: FileEncryptedGetRequest.java#L144-L181
    private func handleEncryptedData(_ data: Data) {
        guard let decrypt = cipher, let originalIV = originalIV else {
            logger.error("Activity", "Encryption not initialized")
            return
        }
        
        do {
            packetCount += 1
            let decrypted: Data
            
            if packetCount == 1 {
                // First packet - determine IV incrementor
                // Try different IV summands to find the correct one
                // Source: FileEncryptedGetRequest.java#L147-L162
                var foundDecrypted: Data?
                
                for testSummand in 0x1E..<0x30 {
                    let testIV = AESCrypto.incrementedIV(from: originalIV, by: testSummand)
                    let testDecrypted = try decrypt(data, testIV)
                    
                    let currentLength = (fileBuffer?.count ?? 0) + testDecrypted.count - 1
                    let expectedByte: UInt8 = (currentLength == expectedFileSize) ? 0x81 : 0x01
                    
                    if testDecrypted[0] == expectedByte {
                        ivIncrementor = testSummand
                        foundDecrypted = testDecrypted
                        logger.debug("Activity", "Found IV incrementor: 0x\(String(format: "%02X", testSummand))")
                        break
                    }
                }
                
                if let found = foundDecrypted {
                    decrypted = found
                } else {
                    // Fallback - use default and hope for the best
                    let iv = AESCrypto.incrementedIV(from: originalIV, by: ivIncrementor)
                    decrypted = try decrypt(data, iv)
                    logger.warning("Activity", "Could not determine IV incrementor, using default")
                }
            } else {
                // Subsequent packets
                let iv = AESCrypto.incrementedIV(from: originalIV, by: ivIncrementor * packetCount)
                decrypted = try decrypt(data, iv)
            }
            
            // Append decrypted data (skip first byte which is packet marker)
            fileBuffer?.append(decrypted.subdata(in: 1..<decrypted.count))
            
            // Update progress
            if expectedFileSize > 0 {
                progress = 0.1 + (Double(fileBuffer?.count ?? 0) / Double(expectedFileSize)) * 0.7
            }
            
            // Check if last packet
            if (decrypted[0] & 0x80) == 0x80 {
                logger.debug("Activity", "Last data packet received")
            }
            
        } catch {
            logger.error("Activity", "Decryption failed: \(error.localizedDescription)")
            fetchContinuation?.resume(throwing: ActivityFetchError.decryptionFailed(error))
            fetchContinuation = nil
        }
    }
    
    // MARK: - State Management
    
    private func resetState() {
        fileBuffer = nil
        expectedFileSize = 0
        cipher = nil
        originalIV = nil
        packetCount = 0
    }
}

// MARK: - Errors

enum ActivityFetchError: Error, LocalizedError {
    case fetchInProgress
    case notAuthenticated
    case encryptionNotReady
    case timeout
    case fileEmpty
    case lookupFailed(UInt8)
    case getFailed(UInt8)
    case crcMismatch
    case invalidResponse
    case decryptionFailed(Error)
    case fetchFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .fetchInProgress:
            return "Activity fetch already in progress"
        case .notAuthenticated:
            return "Not authenticated with watch"
        case .encryptionNotReady:
            return "Encryption keys not ready - authenticate first"
        case .timeout:
            return "Activity fetch timed out"
        case .fileEmpty:
            return "Activity file is empty"
        case .lookupFailed(let status):
            return "File lookup failed (status: \(status))"
        case .getFailed(let status):
            return "File get failed (status: \(status))"
        case .crcMismatch:
            return "File CRC verification failed"
        case .invalidResponse:
            return "Invalid response from watch"
        case .decryptionFailed(let error):
            return "Decryption failed: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Fetch failed: \(error.localizedDescription)"
        }
    }
}
