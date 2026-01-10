import Foundation
import Combine

/// Handles AES-128 authentication with Fossil Hybrid HR watches
/// Source: VerifyPrivateKeyRequest.java#L40-L134
/// https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/authentication/VerifyPrivateKeyRequest.java
@MainActor
final class AuthenticationManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isAuthenticated = false
    @Published private(set) var authState: AuthState = .idle
    @Published private(set) var lastError: AuthError?
    
    // MARK: - Types
    
    enum AuthState {
        case idle
        case sendingChallenge
        case awaitingResponse
        case verifying
        case authenticated
        case failed
    }
    
    // MARK: - Private Properties

    private let bluetoothManager: BluetoothManager
    private let logger = LogManager.shared
    private var secretKey: Data?
    private var phoneRandomNumber: Data?
    private var watchRandomNumber: Data?
    private var authContinuation: CheckedContinuation<Void, Error>?
    
    /// Flag to prevent concurrent authentication attempts
    private var isAuthenticating = false
    
    // MARK: - Initialization
    
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }
    
    // MARK: - Public API
    
    /// Set the device secret key (16 bytes / 32 hex characters)
    func setSecretKey(_ hexKey: String) throws {
        let cleanKey = hexKey
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "0x", with: "")
        
        guard cleanKey.count == 32 else {
            throw AuthError.invalidKeyFormat
        }
        
        guard let keyData = Data(hexString: cleanKey) else {
            throw AuthError.invalidKeyFormat
        }
        
        self.secretKey = keyData
        logger.info("Auth", "Secret key set (\(keyData.count) bytes)")
        logger.debug("Auth", "Key hex: \(keyData.prefix(8).hexString)...")
    }
    
    /// Perform authentication with the watch
    /// This should be called after characteristics are discovered
    func authenticate() async throws {
        // Prevent concurrent authentication attempts
        guard !isAuthenticating else {
            logger.warning("Auth", "Authentication already in progress, ignoring duplicate request")
            return
        }
        
        // Also skip if already authenticated
        guard !isAuthenticated else {
            logger.info("Auth", "Already authenticated, skipping")
            return
        }
        
        try await performAuthHandshake()
    }
    
    /// Verify/refresh authentication - always performs handshake to get fresh randoms
    /// This is equivalent to Gadgetbridge's VerifyPrivateKeyRequest
    /// Source: VerifyPrivateKeyRequest.java - called before every encrypted file operation
    func verifyAuthentication() async throws {
        // Prevent concurrent authentication attempts
        guard !isAuthenticating else {
            logger.warning("Auth", "Authentication already in progress, ignoring duplicate request")
            return
        }
        
        logger.info("Auth", "Verifying authentication (refreshing randoms)...")
        try await performAuthHandshake()
    }
    
    /// Internal method that performs the actual auth handshake
    private func performAuthHandshake() async throws {
        logger.info("Auth", "Starting authentication process")
        isAuthenticating = true

        guard let key = secretKey else {
            logger.error("Auth", "No secret key configured")
            isAuthenticating = false
            throw AuthError.noSecretKey
        }

        logger.debug("Auth", "Secret key available, proceeding with authentication")
        authState = .sendingChallenge

        // Generate 8 random bytes for challenge
        phoneRandomNumber = AESCrypto.generateRandomBytes(count: 8)
        logger.debug("Auth", "Generated phone random number: \(phoneRandomNumber!.hexString)")
        
        // Register handler for authentication responses
        logger.debug("Auth", "Registering notification handler for authentication characteristic")
        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicAuthentication) { [weak self] data in
            Task { @MainActor in
                self?.handleAuthResponse(data)
            }
        }

        // Note: Notifications are already enabled during connection setup in BluetoothManager
        // Do NOT call enableNotifications again here - it can cause issues with iOS CoreBluetooth
        // when dealing with indicate characteristics
        logger.debug("Auth", "Using existing notification subscription for authentication characteristic")

        // Build and send start sequence
        let startSequence = buildStartSequence()
        logger.info("Auth", "Sending authentication challenge (length: \(startSequence.count) bytes)")
        logger.debug("Auth", "Challenge data: \(startSequence.hexString)")

        try await bluetoothManager.write(
            data: startSequence,
            to: FossilConstants.characteristicAuthentication
        )

        authState = .awaitingResponse
        logger.info("Auth", "Challenge sent, awaiting watch response...")
        
        // Wait for authentication to complete
        logger.debug("Auth", "Waiting for authentication to complete (10 second timeout)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.authContinuation = continuation

            // Set timeout
            Task {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if self.authState == .awaitingResponse {
                    self.logger.error("Auth", "Authentication timed out after 10 seconds")
                    self.logger.error("Auth", "Auth state: \(String(describing: self.authState))")
                    self.logger.error("Auth", "Phone random: \(self.phoneRandomNumber?.hexString ?? "nil")")
                    self.logger.error("Auth", "Watch random: \(self.watchRandomNumber?.hexString ?? "nil")")
                    self.authContinuation?.resume(throwing: AuthError.timeout)
                    self.authContinuation = nil
                    self.authState = .failed
                }
            }
        }
    }
    
    /// Get the phone random number (needed for file encryption IV)
    func getPhoneRandomNumber() -> Data? {
        phoneRandomNumber
    }
    
    /// Get the watch random number (needed for file encryption IV)
    func getWatchRandomNumber() -> Data? {
        watchRandomNumber
    }

    /// Expose the negotiated secret key for encrypted file transfers
    func getSecretKey() -> Data? {
        secretKey
    }

    /// Reset authentication state (called on disconnect)
    func resetAuthState() {
        isAuthenticated = false
        isAuthenticating = false
        authState = .idle
        phoneRandomNumber = nil
        watchRandomNumber = nil
        lastError = nil
        logger.debug("Auth", "Authentication state reset")
    }

    // MARK: - Private Methods
    
    /// Build the authentication start sequence
    /// Source: VerifyPrivateKeyRequest.java getStartSequence()
    private func buildStartSequence() -> Data {
        var buffer = ByteBuffer(capacity: 11)
        buffer.putUInt8(0x02)  // Request type
        buffer.putUInt8(0x01)  // Auth command
        buffer.putUInt8(0x01)  // Sub-command
        buffer.putData(phoneRandomNumber!)  // 8 random bytes
        return buffer.data
    }
    
    /// Handle authentication response from watch
    private func handleAuthResponse(_ data: Data) {
        logger.debug("Auth", "Received response from watch (length: \(data.count) bytes)")
        logger.debug("Auth", "Response data: \(data.hexString)")

        guard data.count >= 2 else {
            logger.error("Auth", "Response too short: \(data.count) bytes")
            failAuth(with: .invalidResponse)
            return
        }

        let byte0 = data[0]
        let byte1 = data[1]
        let byte2 = data.count >= 3 ? data[2] : 0
        let byte3 = data.count >= 4 ? data[3] : 0

        logger.info("Auth", "Response bytes: [0]=0x\(String(format: "%02X", byte0)), [1]=0x\(String(format: "%02X", byte1)), [2]=0x\(String(format: "%02X", byte2)), [3]=0x\(String(format: "%02X", byte3))")

        // Source: VerifyPrivateKeyRequest.java#L63
        // Gadgetbridge checks value[1] == 1 for encrypted challenge
        // and value[1] == 2 for authentication result

        // Check for encrypted challenge (byte[1] == 1)
        if byte1 == 0x01 && data.count >= 20 {
            logger.info("Auth", "Received encrypted challenge from watch (byte[1]=0x01)")
            handleChallenge(data)
        }
        // Check for auth result (byte[1] == 2)
        else if byte1 == 0x02 {
            logger.info("Auth", "Received authentication result from watch (byte[1]=0x02)")
            handleAuthResult(data)
        }
        else {
            logger.warning("Auth", "Unknown response format")
            logger.debug("Auth", "Full response: \(data.hexString)")
        }
    }
    
    /// Process the encrypted challenge from the watch
    private func handleChallenge(_ data: Data) {
        logger.info("Auth", "Processing encrypted challenge from watch")

        guard let key = secretKey else {
            logger.error("Auth", "No secret key available for decryption")
            failAuth(with: .noSecretKey)
            return
        }

        authState = .verifying

        // Source: VerifyPrivateKeyRequest.java#L65
        // Extract 16 encrypted bytes starting at position 4 (not position 2!)
        guard data.count >= 20 else {
            logger.error("Auth", "Response too short for encrypted challenge: \(data.count) bytes")
            failAuth(with: .invalidResponse)
            return
        }

        let encryptedChallenge = data.subdata(in: 4..<20)
        logger.debug("Auth", "Encrypted challenge (from byte 4): \(encryptedChallenge.hexString)")

        do {
            // Decrypt the challenge
            let decrypted = try AESCrypto.decryptCBC(data: encryptedChallenge, key: key)
            logger.debug("Auth", "Decrypted challenge: \(decrypted.hexString)")

            // Extract watch random number (first 8 bytes) and verify phone random (last 8 bytes)
            watchRandomNumber = decrypted.subdata(in: 0..<8)
            let echoedPhoneRandom = decrypted.subdata(in: 8..<16)

            logger.debug("Auth", "Watch random number: \(watchRandomNumber!.hexString)")
            logger.debug("Auth", "Echoed phone random: \(echoedPhoneRandom.hexString)")
            logger.debug("Auth", "Original phone random: \(phoneRandomNumber!.hexString)")

            // Verify the echoed phone random matches what we sent
            guard echoedPhoneRandom == phoneRandomNumber else {
                logger.error("Auth", "Phone random number mismatch!")
                logger.error("Auth", "Expected: \(phoneRandomNumber!.hexString)")
                logger.error("Auth", "Received: \(echoedPhoneRandom.hexString)")
                failAuth(with: .verificationFailed)
                return
            }

            logger.info("Auth", "✅ Phone random verification successful")

            // Source: VerifyPrivateKeyRequest.java#L76-L77
            // Swap halves: result[0-7] goes to bytesToEncrypt[8-15]
            //             result[8-15] goes to bytesToEncrypt[0-7]
            var swapped = Data(count: 16)
            swapped.replaceSubrange(0..<8, with: decrypted.subdata(in: 8..<16))
            swapped.replaceSubrange(8..<16, with: decrypted.subdata(in: 0..<8))
            logger.debug("Auth", "Swapped data: \(swapped.hexString)")

            // Re-encrypt
            let encrypted = try AESCrypto.encryptCBC(data: swapped, key: key)
            logger.debug("Auth", "Re-encrypted response: \(encrypted.hexString)")

            // Verify encryption by decrypting again
            let verifyDecrypt = try AESCrypto.decryptCBC(data: encrypted, key: key)
            logger.debug("Auth", "Verification decrypt: \(verifyDecrypt.hexString)")
            logger.debug("Auth", "Should match swapped: \(swapped.hexString)")

            // Source: VerifyPrivateKeyRequest.java#L88-L92
            // Build response: payload[0]=2, payload[1]=2, payload[2]=1, payload[3-18]=encrypted
            var response = Data(capacity: 19)
            response.append(0x02)  // Response type
            response.append(0x02)  // Auth response
            response.append(0x01)  // Status
            response.append(encrypted)

            logger.info("Auth", "Sending authentication response to watch")
            logger.debug("Auth", "Response data: \(response.hexString)")

            // Send response
            Task {
                do {
                    try await bluetoothManager.write(
                        data: response,
                        to: FossilConstants.characteristicAuthentication
                    )
                    self.logger.info("Auth", "✅ Authentication response sent successfully")
                } catch {
                    self.logger.error("Auth", "Failed to send response: \(error.localizedDescription)")
                    failAuth(with: .writeFailed(error))
                }
            }

        } catch {
            logger.error("Auth", "Decryption failed: \(error.localizedDescription)")
            failAuth(with: .decryptionFailed(error))
        }
    }
    
    /// Handle the final authentication result
    private func handleAuthResult(_ data: Data) {
        logger.info("Auth", "Processing authentication result")

        guard data.count >= 3 else {
            logger.error("Auth", "Auth result data too short: \(data.count) bytes")
            failAuth(with: .invalidResponse)
            return
        }

        let status = data[2]
        logger.debug("Auth", "Result status byte: 0x\(String(format: "%02X", status))")

        // Source: VerifyPrivateKeyRequest.java#L106-L110
        // ResultCode.fromCode(value[2]) - status 0x00 means SUCCESS
        if status == 0x00 {
            // Success
            logger.info("Auth", "✅ Authentication successful!")
            logger.info("Auth", "Watch authenticated and ready for communication")
            authState = .authenticated
            isAuthenticated = true
            isAuthenticating = false
            authContinuation?.resume()
            authContinuation = nil
        } else {
            // Failed
            logger.error("Auth", "❌ Authentication rejected by watch")
            logger.error("Auth", "Status code: 0x\(String(format: "%02X", status))")
            logger.error("Auth", "Full response: \(data.hexString)")
            logger.error("Auth", "")
            logger.error("Auth", "Common causes of authentication rejection:")
            logger.error("Auth", "1. Incorrect secret key - verify the key matches this specific watch")
            logger.error("Auth", "2. Watch was previously paired with different phone - may need factory reset")
            logger.error("Auth", "3. Key from Gadgetbridge database may be for wrong device")
            failAuth(with: .rejected)
        }
    }

    // MARK: - Post-Auth Device Confirmation & Pairing
    
    /// Perform device confirmation and pairing after authentication
    /// Source: FossilHRWatchAdapter.java initializeAfterAuthentication() flow
    /// This must be called after successful authentication before accessing encrypted files like CONFIGURATION
    func performPostAuthInitialization() async throws {
        guard isAuthenticated else {
            throw AuthError.noSecretKey
        }
        
        logger.info("Auth", "Starting post-auth initialization...")
        
        // Step 1: Check if device needs confirmation
        // Source: CheckDeviceNeedsConfirmationRequest.java - sends [0x01, 0x07] to 3DDA0005
        logger.info("Auth", "Checking if device needs confirmation...")
        let needsConfirmation = try await checkDeviceNeedsConfirmation()
        
        if needsConfirmation {
            logger.info("Auth", "Device needs confirmation - prompting user...")
            // This prompts a confirmation dialog on the watch
            let confirmed = try await confirmOnDevice()
            if confirmed {
                logger.info("Auth", "✅ User confirmed connection on watch")
                // After confirmation, perform pairing
                try await checkAndPerformPairing()
            } else {
                logger.warning("Auth", "User declined confirmation on watch - trying pairing anyway...")
                // Try pairing anyway - the watch may not actually require confirmation
                // or the confirmation may have been handled previously
                try await checkAndPerformPairing()
            }
        } else {
            logger.info("Auth", "Device does not need confirmation")
            // Still check/perform pairing
            try await checkAndPerformPairing()
        }
        
        logger.info("Auth", "✅ Post-auth initialization complete")
    }
    
    /// Check if the watch needs user confirmation for this connection
    /// Source: CheckDeviceNeedsConfirmationRequest.java
    private func checkDeviceNeedsConfirmation() async throws -> Bool {
        // Send: [0x01, 0x07]
        // Response: [0x03, 0x07, status] where status 0x00 = needs confirmation
        let request = Data([0x01, 0x07])
        logger.debug("Auth", "Sending needs-confirmation check: \(request.hexString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicAuthentication) { [weak self] data in
                guard data.count >= 3, data[0] == 0x03, data[1] == 0x07 else {
                    self?.logger.warning("Auth", "Unexpected confirmation check response: \(data.hexString)")
                    return
                }
                
                let needsConfirmation = data[2] == 0x00
                self?.logger.info("Auth", "Needs confirmation: \(needsConfirmation) (status: 0x\(String(format: "%02X", data[2])))")
                self?.bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicAuthentication)
                continuation.resume(returning: needsConfirmation)
            }
            
            Task {
                do {
                    try await self.bluetoothManager.write(data: request, to: FossilConstants.characteristicAuthentication)
                } catch {
                    self.bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicAuthentication)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Prompt user to confirm connection on the watch
    /// Source: ConfirmOnDeviceRequest.java
    private func confirmOnDevice() async throws -> Bool {
        // Send: [0x02, 0x06, 0x30, 0x75, 0x00, 0x00, 0x00]
        // Response: [0x03, 0x06, 0x00, status] where status 0x01 = confirmed
        let request = Data([0x02, 0x06, 0x30, 0x75, 0x00, 0x00, 0x00])
        logger.debug("Auth", "Sending confirm-on-device request: \(request.hexString)")
        logger.info("Auth", "⌚ Please confirm connection on the watch...")
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            // 30 second timeout for user to confirm
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if !hasResumed {
                    hasResumed = true
                    self?.logger.warning("Auth", "Confirmation timed out")
                    self?.bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicAuthentication)
                    continuation.resume(returning: false)
                }
            }
            
            bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicAuthentication) { [weak self] data in
                guard data.count >= 4, data[0] == 0x03, data[1] == 0x06, data[2] == 0x00 else {
                    self?.logger.warning("Auth", "Unexpected confirmation response: \(data.hexString)")
                    return
                }
                
                guard !hasResumed else { return }
                hasResumed = true
                timeoutTask.cancel()
                let confirmed = data[3] == 0x01
                self?.logger.info("Auth", "User confirmation result: \(confirmed ? "confirmed ✅" : "declined ❌")")
                self?.bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicAuthentication)
                continuation.resume(returning: confirmed)
            }
            
            Task {
                do {
                    try await self.bluetoothManager.write(data: request, to: FossilConstants.characteristicAuthentication)
                } catch {
                    guard !hasResumed else { return }
                    hasResumed = true
                    timeoutTask.cancel()
                    self.bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicAuthentication)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Check device pairing status and perform pairing if needed
    /// Source: CheckDevicePairingRequest.java, PerformDevicePairingRequest.java
    private func checkAndPerformPairing() async throws {
        // Check pairing: send [0x01, 0x16] to 3DDA0002
        // Response: [0x03, 0x16, status] where status 0x01 = paired
        let checkRequest = Data([0x01, 0x16])
        logger.info("Auth", "Checking device pairing status...")
        
        let isPaired = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicControl) { [weak self] data in
                guard data.count >= 3, data[0] == 0x03, data[1] == 0x16 else {
                    self?.logger.warning("Auth", "Unexpected pairing check response: \(data.hexString)")
                    return
                }
                
                let paired = data[2] == 0x01
                self?.logger.info("Auth", "Device pairing status: \(paired ? "paired" : "not paired")")
                self?.bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicControl)
                continuation.resume(returning: paired)
            }
            
            Task {
                do {
                    try await self.bluetoothManager.write(data: checkRequest, to: FossilConstants.characteristicControl)
                } catch {
                    self.bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicControl)
                    continuation.resume(throwing: error)
                }
            }
        }
        
        if !isPaired {
            logger.info("Auth", "Device not paired, performing pairing...")
            try await performPairing()
        } else {
            logger.info("Auth", "✅ Device already paired")
        }
    }
    
    /// Perform device pairing
    /// Source: PerformDevicePairingRequest.java - sends [0x02, 0x16] to 3DDA0002
    private func performPairing() async throws {
        let pairRequest = Data([0x02, 0x16])
        logger.debug("Auth", "Sending pairing request: \(pairRequest.hexString)")
        
        let pairingSuccess = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicControl) { [weak self] data in
                guard data.count >= 3, data[0] == 0x03, data[1] == 0x16 else {
                    self?.logger.warning("Auth", "Unexpected pairing response: \(data.hexString)")
                    return
                }
                
                let success = data[2] == 0x01
                self?.logger.info("Auth", "Pairing result: \(success ? "success" : "failed")")
                self?.bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicControl)
                continuation.resume(returning: success)
            }
            
            Task {
                do {
                    try await self.bluetoothManager.write(data: pairRequest, to: FossilConstants.characteristicControl)
                } catch {
                    self.bluetoothManager.unregisterNotificationHandler(for: FossilConstants.characteristicControl)
                    continuation.resume(throwing: error)
                }
            }
        }
        
        if pairingSuccess {
            logger.info("Auth", "✅ Device pairing successful")
            // Add a small delay after pairing to allow watch to update state
            logger.debug("Auth", "Waiting 500ms for watch state to settle...")
            try? await Task.sleep(nanoseconds: 500_000_000)
        } else {
            logger.error("Auth", "Device pairing failed")
            throw AuthError.rejected
        }
    }

    private func failAuth(with error: AuthError) {
        logger.error("Auth", "Authentication failed: \(error.localizedDescription)")
        logger.error("Auth", "Final state - phoneRandom: \(phoneRandomNumber?.hexString ?? "nil"), watchRandom: \(watchRandomNumber?.hexString ?? "nil")")
        lastError = error
        authState = .failed
        isAuthenticated = false
        isAuthenticating = false
        authContinuation?.resume(throwing: error)
        authContinuation = nil
    }
}

// MARK: - Errors

enum AuthError: Error, LocalizedError {
    case noSecretKey
    case invalidKeyFormat
    case invalidResponse
    case timeout
    case verificationFailed
    case decryptionFailed(Error)
    case writeFailed(Error)
    case rejected
    
    var errorDescription: String? {
        switch self {
        case .noSecretKey:
            return "No secret key configured. Please import your device key."
        case .invalidKeyFormat:
            return "Invalid key format. Key must be 32 hex characters (16 bytes)."
        case .invalidResponse:
            return "Invalid response from watch"
        case .timeout:
            return "Authentication timed out"
        case .verificationFailed:
            return "Challenge verification failed - wrong key?"
        case .decryptionFailed(let error):
            return "Decryption failed: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to send response: \(error.localizedDescription)"
        case .rejected:
            return "Authentication rejected by watch"
        }
    }
}
