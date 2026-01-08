import Foundation

/// Helper for building and parsing little-endian byte buffers
/// The Fossil protocol uses little-endian byte order for all multi-byte values
struct ByteBuffer {
    private(set) var bytes: [UInt8]
    private var readPosition: Int = 0
    
    // MARK: - Initialization
    
    init(capacity: Int = 64) {
        bytes = []
        bytes.reserveCapacity(capacity)
    }
    
    init(data: Data) {
        bytes = [UInt8](data)
    }
    
    init(bytes: [UInt8]) {
        self.bytes = bytes
    }
    
    // MARK: - Write Operations (Little-Endian)
    
    mutating func putUInt8(_ value: UInt8) {
        bytes.append(value)
    }
    
    mutating func putInt8(_ value: Int8) {
        bytes.append(UInt8(bitPattern: value))
    }
    
    mutating func putUInt16(_ value: UInt16) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
    }
    
    mutating func putInt16(_ value: Int16) {
        putUInt16(UInt16(bitPattern: value))
    }
    
    mutating func putUInt32(_ value: UInt32) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 24) & 0xFF))
    }
    
    mutating func putInt32(_ value: Int32) {
        putUInt32(UInt32(bitPattern: value))
    }
    
    mutating func putBytes(_ data: [UInt8]) {
        bytes.append(contentsOf: data)
    }
    
    mutating func putData(_ data: Data) {
        bytes.append(contentsOf: data)
    }
    
    /// Write a null-terminated UTF-8 string
    mutating func putNullTerminatedString(_ string: String) {
        if let data = string.data(using: .utf8) {
            bytes.append(contentsOf: data)
        }
        bytes.append(0x00)  // Null terminator
    }
    
    // MARK: - Read Operations (Little-Endian)
    
    mutating func getUInt8() -> UInt8? {
        guard readPosition < bytes.count else { return nil }
        let value = bytes[readPosition]
        readPosition += 1
        return value
    }
    
    mutating func getInt8() -> Int8? {
        guard let value = getUInt8() else { return nil }
        return Int8(bitPattern: value)
    }
    
    mutating func getUInt16() -> UInt16? {
        guard readPosition + 1 < bytes.count else { return nil }
        let low = UInt16(bytes[readPosition])
        let high = UInt16(bytes[readPosition + 1])
        readPosition += 2
        return low | (high << 8)
    }
    
    mutating func getInt16() -> Int16? {
        guard let value = getUInt16() else { return nil }
        return Int16(bitPattern: value)
    }
    
    mutating func getUInt32() -> UInt32? {
        guard readPosition + 3 < bytes.count else { return nil }
        let b0 = UInt32(bytes[readPosition])
        let b1 = UInt32(bytes[readPosition + 1])
        let b2 = UInt32(bytes[readPosition + 2])
        let b3 = UInt32(bytes[readPosition + 3])
        readPosition += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
    
    mutating func getInt32() -> Int32? {
        guard let value = getUInt32() else { return nil }
        return Int32(bitPattern: value)
    }
    
    mutating func getBytes(_ count: Int) -> [UInt8]? {
        guard readPosition + count <= bytes.count else { return nil }
        let result = Array(bytes[readPosition..<(readPosition + count)])
        readPosition += count
        return result
    }
    
    /// Read a null-terminated UTF-8 string
    mutating func getNullTerminatedString() -> String? {
        var stringBytes: [UInt8] = []
        while readPosition < bytes.count {
            let byte = bytes[readPosition]
            readPosition += 1
            if byte == 0x00 {
                break
            }
            stringBytes.append(byte)
        }
        return String(bytes: stringBytes, encoding: .utf8)
    }
    
    // MARK: - Utility
    
    var data: Data {
        Data(bytes)
    }
    
    var count: Int {
        bytes.count
    }
    
    var isEmpty: Bool {
        bytes.isEmpty
    }
    
    var remainingBytes: Int {
        bytes.count - readPosition
    }
    
    mutating func resetReadPosition() {
        readPosition = 0
    }
    
    mutating func clear() {
        bytes.removeAll()
        readPosition = 0
    }
}

// MARK: - Data Extension

extension Data {
    /// Convert to hex string for debugging
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// Create from hex string
    init?(hexString: String) {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "0x", with: "")
        
        guard cleanHex.count % 2 == 0 else { return nil }
        
        var data = Data()
        var index = cleanHex.startIndex
        
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            guard let byte = UInt8(cleanHex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}
