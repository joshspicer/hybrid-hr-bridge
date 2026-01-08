import Foundation
import zlib

/// CRC32 and CRC32C implementations for Fossil protocol
/// The protocol uses CRC32 for package names and CRC32C for file integrity
struct CRC32 {
    
    // MARK: - CRC32 (Standard)
    
    /// Calculate standard CRC32 checksum
    /// Used for package name hashing in notifications
    static func checksum(_ data: Data) -> UInt32 {
        let crc = zlib.crc32(0, [UInt8](data), UInt32(data.count))
        return UInt32(crc)
    }
    
    /// Calculate CRC32 of a string (UTF-8 encoded)
    static func checksum(_ string: String) -> UInt32 {
        guard let data = string.data(using: .utf8) else { return 0 }
        return checksum(data)
    }
    
    // MARK: - CRC32C (Castagnoli)
    
    /// CRC32C lookup table (Castagnoli polynomial: 0x1EDC6F41)
    private static let crc32cTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        let polynomial: UInt32 = 0x82F63B78  // Reversed polynomial
        
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ polynomial
                } else {
                    crc >>= 1
                }
            }
            table[i] = crc
        }
        return table
    }()
    
    /// Calculate CRC32C checksum (Castagnoli variant)
    /// Used for file data integrity in the Fossil protocol
    /// Source: FossilAppWriter.java - uses CRC32C for file verification
    static func checksumC(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crc32cTable[index]
        }
        
        return crc ^ 0xFFFFFFFF
    }
    
    /// Calculate CRC32C of a byte array
    static func checksumC(_ bytes: [UInt8]) -> UInt32 {
        checksumC(Data(bytes))
    }
}

// MARK: - Convenience Extensions

extension Data {
    /// Calculate CRC32 checksum of this data
    var crc32: UInt32 {
        CRC32.checksum(self)
    }
    
    /// Calculate CRC32C checksum of this data
    var crc32c: UInt32 {
        CRC32.checksumC(self)
    }
}

extension String {
    /// Calculate CRC32 of the UTF-8 encoded string
    /// Used for package name hashing in notification filters
    var crc32: UInt32 {
        CRC32.checksum(self)
    }
}
