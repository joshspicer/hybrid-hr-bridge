import Foundation
import CoreBluetooth

/// Handles encrypted file reading from Fossil Hybrid HR watch
/// Manages the two-phase process: file lookup followed by encrypted get
/// Source: FileEncryptedLookupAndGetRequest.java
@MainActor
final class EncryptedFileReader {

    // MARK: - Dependencies

    private let bluetoothManager: BluetoothManager
    private let authManager: AuthenticationManager
    private let logger = LogManager.shared

    // MARK: - State

    private var readState: EncryptedReadState?
    private var readContinuation: CheckedContinuation<Data, Error>?
    private var readTimeoutTask: Task<Void, Never>?

    // MARK: - Initialization

    init(bluetoothManager: BluetoothManager, authManager: AuthenticationManager) {
        self.bluetoothManager = bluetoothManager
        self.authManager = authManager
    }

    // MARK: - Public API

    /// Fetch an encrypted file from the watch
    /// This performs a file lookup followed by an encrypted get request
    /// Source: FossilHRWatchAdapter.java#L1166-1182 - queueWrite(FileEncryptedInterface) calls VerifyPrivateKeyRequest first
    /// CRITICAL: In Gadgetbridge, VerifyPrivateKeyRequest is called IMMEDIATELY before each encrypted file operation
    func fetchEncryptedFile(for handle: FileHandle) async throws -> Data {
        logger.info("Protocol", "=== Starting encrypted file fetch for \(handle) ===")

        guard authManager.isAuthenticated else {
            logger.error("Protocol", "Not authenticated, cannot fetch encrypted file")
            throw FileTransferError.notAuthenticated
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

    // MARK: - Response Handlers

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

    // MARK: - Decryption

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

    // MARK: - Cleanup

    private func cleanupReadHandlers() {
        bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicFileOperations)
        bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicFileData)
        readTimeoutTask?.cancel()
        readTimeoutTask = nil
    }

    private func failRead(with error: FileTransferError) {
        guard readState != nil else { return }

        logger.error("Protocol", "Encrypted read failed: \(error.localizedDescription)")
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
