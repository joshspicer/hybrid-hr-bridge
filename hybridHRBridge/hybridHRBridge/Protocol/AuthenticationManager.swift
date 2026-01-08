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
    private var secretKey: Data?
    private var phoneRandomNumber: Data?
    private var watchRandomNumber: Data?
    private var authContinuation: CheckedContinuation<Void, Error>?
    
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
        print("[Auth] Secret key set (\(keyData.count) bytes)")
    }
    
    /// Perform authentication with the watch
    /// This should be called after characteristics are discovered
    func authenticate() async throws {
        guard let key = secretKey else {
            throw AuthError.noSecretKey
        }
        
        authState = .sendingChallenge
        
        // Generate 8 random bytes for challenge
        phoneRandomNumber = AESCrypto.generateRandomBytes(count: 8)
        
        // Register handler for authentication responses
        bluetoothManager.registerNotificationHandler(for: FossilConstants.characteristicAuthentication) { [weak self] data in
            Task { @MainActor in
                self?.handleAuthResponse(data)
            }
        }
        
        // Enable notifications for auth characteristic
        try await bluetoothManager.enableNotifications(for: FossilConstants.characteristicAuthentication)
        
        // Build and send start sequence
        let startSequence = buildStartSequence()
        print("[Auth] Sending challenge: \(startSequence.hexString)")
        
        try await bluetoothManager.write(
            data: startSequence,
            to: FossilConstants.characteristicAuthentication
        )
        
        authState = .awaitingResponse
        
        // Wait for authentication to complete
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.authContinuation = continuation
            
            // Set timeout
            Task {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if self.authState == .awaitingResponse {
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
        guard data.count >= 2 else {
            failAuth(with: .invalidResponse)
            return
        }
        
        let responseType = data[0]
        let subType = data[1]
        
        print("[Auth] Received response type: \(responseType), subType: \(subType)")
        
        // Check for encrypted challenge (response type 2, subtype 1)
        if responseType == 0x02 && subType == 0x01 && data.count >= 18 {
            handleChallenge(data)
        }
        // Check for auth result (response type 2, subtype 2 or 3)
        else if responseType == 0x02 && (subType == 0x02 || subType == 0x03) {
            handleAuthResult(data)
        }
        else {
            print("[Auth] Unknown response: \(data.hexString)")
        }
    }
    
    /// Process the encrypted challenge from the watch
    private func handleChallenge(_ data: Data) {
        guard let key = secretKey else {
            failAuth(with: .noSecretKey)
            return
        }
        
        authState = .verifying
        
        // Extract 16 encrypted bytes (starting at byte 2)
        let encryptedChallenge = data.subdata(in: 2..<18)
        
        do {
            // Decrypt the challenge
            let decrypted = try AESCrypto.decryptCBC(data: encryptedChallenge, key: key)
            print("[Auth] Decrypted challenge: \(decrypted.hexString)")
            
            // Extract watch random number (first 8 bytes) and verify phone random (last 8 bytes)
            watchRandomNumber = decrypted.subdata(in: 0..<8)
            let echoedPhoneRandom = decrypted.subdata(in: 8..<16)
            
            // Verify the echoed phone random matches what we sent
            guard echoedPhoneRandom == phoneRandomNumber else {
                print("[Auth] Phone random mismatch!")
                failAuth(with: .verificationFailed)
                return
            }
            
            // Swap halves: first 8 bytes ↔ last 8 bytes
            var swapped = Data(count: 16)
            swapped.replaceSubrange(0..<8, with: decrypted.subdata(in: 8..<16))
            swapped.replaceSubrange(8..<16, with: decrypted.subdata(in: 0..<8))
            
            // Re-encrypt
            let encrypted = try AESCrypto.encryptCBC(data: swapped, key: key)
            
            // Build response
            var response = Data(capacity: 19)
            response.append(0x02)  // Response type
            response.append(0x02)  // Auth response
            response.append(0x01)  // Status
            response.append(encrypted)
            
            print("[Auth] Sending response: \(response.hexString)")
            
            // Send response
            Task {
                do {
                    try await bluetoothManager.write(
                        data: response,
                        to: FossilConstants.characteristicAuthentication
                    )
                } catch {
                    failAuth(with: .writeFailed(error))
                }
            }
            
        } catch {
            failAuth(with: .decryptionFailed(error))
        }
    }
    
    /// Handle the final authentication result
    private func handleAuthResult(_ data: Data) {
        guard data.count >= 3 else {
            failAuth(with: .invalidResponse)
            return
        }
        
        let status = data[2]
        
        if status == 0x01 {
            // Success
            print("[Auth] Authentication successful!")
            authState = .authenticated
            isAuthenticated = true
            authContinuation?.resume()
            authContinuation = nil
        } else {
            // Failed
            print("[Auth] Authentication failed with status: \(status)")
            failAuth(with: .rejected)
        }
    }
    
    private func failAuth(with error: AuthError) {
        lastError = error
        authState = .failed
        isAuthenticated = false
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
