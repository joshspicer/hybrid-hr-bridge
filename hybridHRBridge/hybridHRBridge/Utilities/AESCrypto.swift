import Foundation
import CryptoKit
import CommonCrypto

/// AES encryption utilities for Fossil Hybrid HR authentication
/// The watch uses AES-128 CBC with zero IV for the authentication handshake
/// and AES-128 CTR for encrypted file transfers
/// Source: VerifyPrivateKeyRequest.java#L40-L134
struct AESCrypto {
    
    /// Zero IV used for authentication (16 bytes of 0x00)
    static let zeroIV = Data(repeating: 0x00, count: 16)
    
    // MARK: - AES-128 CBC (Authentication)
    
    /// Encrypt data using AES-128 CBC with zero IV
    /// Used in authentication response
    static func encryptCBC(data: Data, key: Data) throws -> Data {
        guard key.count == 16 else {
            throw AESError.invalidKeySize
        }
        guard data.count % 16 == 0 else {
            throw AESError.invalidDataSize
        }
        
        let outputSize = data.count
        var encryptedBytes = [UInt8](repeating: 0, count: outputSize)
        var numBytesEncrypted: size_t = 0
        
        let status = data.withUnsafeBytes { dataBuffer in
            key.withUnsafeBytes { keyBuffer in
                zeroIV.withUnsafeBytes { ivBuffer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(0),  // No padding - NoPadding
                        keyBuffer.baseAddress, key.count,
                        ivBuffer.baseAddress,
                        dataBuffer.baseAddress, data.count,
                        &encryptedBytes, outputSize,
                        &numBytesEncrypted
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw AESError.encryptionFailed(status: Int(status))
        }
        
        return Data(encryptedBytes)
    }
    
    /// Decrypt data using AES-128 CBC with zero IV
    /// Used to decrypt watch challenge in authentication
    static func decryptCBC(data: Data, key: Data) throws -> Data {
        guard key.count == 16 else {
            throw AESError.invalidKeySize
        }
        guard data.count % 16 == 0 else {
            throw AESError.invalidDataSize
        }
        
        let outputSize = data.count
        var decryptedBytes = [UInt8](repeating: 0, count: outputSize)
        var numBytesDecrypted: size_t = 0
        
        let status = data.withUnsafeBytes { dataBuffer in
            key.withUnsafeBytes { keyBuffer in
                zeroIV.withUnsafeBytes { ivBuffer in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(0),  // No padding - NoPadding
                        keyBuffer.baseAddress, key.count,
                        ivBuffer.baseAddress,
                        dataBuffer.baseAddress, data.count,
                        &decryptedBytes, outputSize,
                        &numBytesDecrypted
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw AESError.decryptionFailed(status: Int(status))
        }
        
        return Data(decryptedBytes)
    }
    
    // MARK: - AES-128 CTR (File Encryption)
    
    /// Encrypt/decrypt data using AES-128 CTR mode
    /// Used for encrypted file transfers after authentication
    /// Source: FileEncryptedGetRequest.java#L82-L107
    static func cryptCTR(data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 16 else {
            throw AESError.invalidKeySize
        }
        guard iv.count == 16 else {
            throw AESError.invalidIVSize
        }
        
        let outputSize = data.count
        var resultBytes = [UInt8](repeating: 0, count: outputSize)
        var numBytesProcessed: size_t = 0
        
        // Create cryptor for CTR mode
        var cryptorRef: CCCryptorRef?
        
        let createStatus = key.withUnsafeBytes { keyBuffer in
            iv.withUnsafeBytes { ivBuffer in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),  // CTR mode is symmetric
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBuffer.baseAddress,
                    keyBuffer.baseAddress, key.count,
                    nil, 0, 0,
                    CCModeOptions(kCCModeOptionCTR_BE),  // Big-endian counter
                    &cryptorRef
                )
            }
        }
        
        guard createStatus == kCCSuccess, let cryptor = cryptorRef else {
            throw AESError.cryptorCreationFailed(status: Int(createStatus))
        }
        
        defer { CCCryptorRelease(cryptor) }
        
        let updateStatus = data.withUnsafeBytes { dataBuffer in
            CCCryptorUpdate(
                cryptor,
                dataBuffer.baseAddress, data.count,
                &resultBytes, outputSize,
                &numBytesProcessed
            )
        }
        
        guard updateStatus == kCCSuccess else {
            throw AESError.encryptionFailed(status: Int(updateStatus))
        }
        
        return Data(resultBytes)
    }
    
    // MARK: - IV Generation for File Encryption
    
    /// Generate IV for encrypted file transfers
    /// Source: FileEncryptedGetRequest.java#L82-L107
    /// IV composition:
    ///   Bytes 2-7: phoneRandomNumber[0-5]
    ///   Bytes 9-15: watchRandomNumber[0-6]
    ///   Byte 7: incremented
    static func generateFileIV(phoneRandom: Data, watchRandom: Data) -> Data {
        var iv = Data(repeating: 0x00, count: 16)
        
        // Copy phone random bytes to positions 2-7
        for i in 0..<min(6, phoneRandom.count) {
            iv[2 + i] = phoneRandom[i]
        }
        
        // Copy watch random bytes to positions 9-15
        for i in 0..<min(7, watchRandom.count) {
            iv[9 + i] = watchRandom[i]
        }
        
        // Increment byte 7
        iv[7] = iv[7] &+ 1
        
        return iv
    }
    
    /// Increment IV counter for next packet
    /// The IV is incremented by 0x1F per packet in encrypted transfers
    static func incrementIV(_ iv: inout Data, by amount: Int = 0x1F) {
        guard amount >= 0 else { return }

        var carry = amount

        // Increment using big-endian counter semantics (matches Gadgetbridge logic)
        for index in (0..<iv.count).reversed() {
            if carry == 0 { break }

            let sum = Int(iv[index]) + carry
            iv[index] = UInt8(sum & 0xFF)
            carry = sum >> 8
        }
    }

    /// Return a new IV incremented by the supplied amount without mutating the original
    static func incrementedIV(from iv: Data, by amount: Int) -> Data {
        var copy = iv
        incrementIV(&copy, by: amount)
        return copy
    }
    
    // MARK: - Random Number Generation
    
    /// Generate random bytes for authentication
    static func generateRandomBytes(count: Int) -> Data {
        var bytes = Data(count: count)
        _ = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        return bytes
    }
}

// MARK: - Errors

enum AESError: Error, LocalizedError {
    case invalidKeySize
    case invalidIVSize
    case invalidDataSize
    case encryptionFailed(status: Int)
    case decryptionFailed(status: Int)
    case cryptorCreationFailed(status: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidKeySize:
            return "Key must be 16 bytes (128 bits)"
        case .invalidIVSize:
            return "IV must be 16 bytes"
        case .invalidDataSize:
            return "Data size must be multiple of 16 bytes for CBC mode"
        case .encryptionFailed(let status):
            return "Encryption failed with status: \(status)"
        case .decryptionFailed(let status):
            return "Decryption failed with status: \(status)"
        case .cryptorCreationFailed(let status):
            return "Failed to create cryptor with status: \(status)"
        }
    }
}
