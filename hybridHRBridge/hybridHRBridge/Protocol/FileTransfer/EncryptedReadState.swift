import Foundation

/// State tracking for encrypted file read operations
/// Source: FileEncryptedLookupAndGetRequest.java
struct EncryptedReadState {
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
