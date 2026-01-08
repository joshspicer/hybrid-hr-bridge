import Foundation

/// Protocol message builders for Fossil Hybrid HR communication
/// Source: FilePutRawRequest.java, FileGetRawRequest.java, ConfigurationPutRequest.java
struct RequestBuilder {
    
    // MARK: - File Put Request
    
    /// Build a file put request header (15 bytes)
    /// Source: FilePutRawRequest.java#L222-L240
    /// Characteristic: 3dda0003
    static func buildFilePutRequest(handle: FileHandle, data: Data, offset: UInt32 = 0) -> Data {
        var buffer = ByteBuffer(capacity: 15)
        
        buffer.putUInt8(FossilConstants.Command.filePut.rawValue)  // 0x03
        buffer.putUInt16(handle.rawValue)                          // File handle (LE)
        buffer.putUInt32(offset)                                   // File offset (LE)
        buffer.putUInt32(UInt32(data.count))                       // File size (LE)
        buffer.putUInt32(data.crc32c)                              // CRC32C checksum (LE)
        
        return buffer.data
    }
    
    // MARK: - File Get Request
    
    /// Build a file get request header (11 bytes)
    /// Source: FileGetRawRequest.java#L134-L148
    /// Characteristic: 3dda0003
    static func buildFileGetRequest(handle: FileHandle, startOffset: UInt32 = 0, endOffset: UInt32 = 0xFFFFFFFF) -> Data {
        var buffer = ByteBuffer(capacity: 11)
        
        buffer.putUInt8(FossilConstants.Command.fileGet.rawValue)  // 0x01
        buffer.putUInt8(handle.minor)                              // Minor handle
        buffer.putUInt8(handle.major)                              // Major handle
        buffer.putUInt32(startOffset)                              // Start offset (LE)
        buffer.putUInt32(endOffset)                                // End offset (LE)
        
        return buffer.data
    }
    
    // MARK: - Time Configuration
    
    /// Build a time sync configuration payload (8 bytes)
    /// Source: ConfigurationPutRequest.java#L292-L337
    /// Config ID: 0x0C
    static func buildTimeConfig(date: Date = Date(), timeZone: TimeZone = .current) -> Data {
        var buffer = ByteBuffer(capacity: 8)
        
        let epochSeconds = UInt32(date.timeIntervalSince1970)
        let millis = UInt16(Int(date.timeIntervalSince1970 * 1000) % 1000)
        let offsetMinutes = Int16(timeZone.secondsFromGMT(for: date) / 60)
        
        buffer.putUInt32(epochSeconds)        // Unix timestamp (LE)
        buffer.putUInt16(millis)              // Milliseconds (LE)
        buffer.putInt16(offsetMinutes)        // Timezone offset in minutes (LE)
        
        return buffer.data
    }
    
    /// Build a full configuration put request with time config
    static func buildTimeSyncRequest(date: Date = Date(), timeZone: TimeZone = .current) -> Data {
        let timeData = buildTimeConfig(date: date, timeZone: timeZone)
        return buildConfigurationRequest(itemID: .timeConfig, data: timeData)
    }
    
    // MARK: - Configuration Request
    
    /// Build a configuration item request
    /// Source: ConfigurationPutRequest.java
    static func buildConfigurationRequest(itemID: FossilConstants.ConfigItemID, data: Data) -> Data {
        var buffer = ByteBuffer(capacity: 4 + data.count)
        
        buffer.putUInt8(0x02)                 // Config put command
        buffer.putUInt8(itemID.rawValue)      // Config item ID
        buffer.putUInt16(UInt16(data.count))  // Data length (LE)
        buffer.putData(data)                  // Config data
        
        return buffer.data
    }
    
    // MARK: - Notification Request
    
    /// Build a notification payload
    /// Source: PlayNotificationRequest.java#L54-L92
    /// File Handle: 0x0900 (NOTIFICATION_PLAY)
    static func buildNotification(
        type: NotificationType,
        title: String,
        sender: String,
        message: String,
        packageCRC: UInt32,
        messageID: UInt32,
        flags: UInt8 = 0
    ) -> Data {
        // Truncate message to 475 chars max
        let truncatedMessage = String(message.prefix(475))
        
        // Encode strings as null-terminated UTF-8
        let titleBytes = (title + "\0").data(using: .utf8) ?? Data([0])
        let senderBytes = (sender + "\0").data(using: .utf8) ?? Data([0])
        let messageBytes = (truncatedMessage + "\0").data(using: .utf8) ?? Data([0])
        
        let payloadLength = 10 + titleBytes.count + senderBytes.count + messageBytes.count
        
        var buffer = ByteBuffer(capacity: payloadLength)
        
        // Header (10 bytes excluding length field)
        buffer.putUInt16(UInt16(payloadLength - 2))  // Payload length (excludes these 2 bytes)
        buffer.putUInt8(flags)                        // Flags
        buffer.putUInt8(type.rawValue)                // Notification type
        buffer.putUInt32(messageID)                   // Unique message ID
        buffer.putUInt16(UInt16(titleBytes.count))    // Title length
        buffer.putUInt32(packageCRC)                  // Package CRC32
        
        // String data
        buffer.putData(titleBytes)
        buffer.putData(senderBytes)
        buffer.putData(messageBytes)
        
        return buffer.data
    }
    
    // MARK: - Connection Parameters
    
    /// Build connection parameters request
    /// Source: SetConnectionParametersRequest.java#L44-L46
    /// Characteristic: 3dda0002
    static func buildConnectionParametersRequest() -> Data {
        Data(FossilConstants.connectionParametersPayload)
    }
    
    // MARK: - App File (.wapp)
    
    /// Build a .wapp file header for app upload
    /// Source: FossilAppWriter.java#L63-L120
    /// File Handle: 0x15FE (APP_CODE)
    static func buildAppFileHeader(appData: Data) -> Data {
        var buffer = ByteBuffer(capacity: 12)
        
        buffer.putUInt8(0xFE)                  // Handle low byte
        buffer.putUInt8(0x15)                  // Handle high byte
        buffer.putUInt16(0x0003)               // File version
        buffer.putUInt32(0)                    // File offset
        buffer.putUInt32(UInt32(appData.count)) // File size
        
        return buffer.data
    }
    
    /// Build complete .wapp file
    static func buildWappFile(appData: Data) -> Data {
        var buffer = ByteBuffer(capacity: 12 + appData.count + 4)
        
        // Header
        buffer.putData(buildAppFileHeader(appData: appData))
        
        // App data
        buffer.putData(appData)
        
        // CRC32C of app data
        buffer.putUInt32(appData.crc32c)
        
        return buffer.data
    }
}

// MARK: - Notification Type

/// Notification types for the watch
/// Source: NotificationType.java#L18-L37
enum NotificationType: UInt8 {
    case incomingCall = 1
    case text = 2
    case notification = 3
    case email = 4
    case calendar = 5
    case missedCall = 6
    case dismissNotification = 7
}
