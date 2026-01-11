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
        buffer.putUInt32(UInt32(data.count))                       // File size repeated

        return buffer.data
    }
    
    // MARK: - File Get Request
    
    /// Build a file lookup request to resolve dynamic handles
    /// Source: FileLookupRequest.java
    static func buildFileLookupRequest(for handle: FileHandle) -> Data {
        var buffer = ByteBuffer(capacity: 3)
        buffer.putUInt8(0x02)
        buffer.putUInt8(0xFF)
        buffer.putUInt8(handle.major)
        return buffer.data
    }

    /// Build a file get request header (11 bytes)
    /// Source: FileGetRawRequest.java#L134-L148
    /// Characteristic: 3dda0003
    static func buildFileGetRequest(handle: FileHandle, startOffset: UInt32 = 0, endOffset: UInt32 = 0xFFFFFFFF) -> Data {
        buildFileGetRequest(major: handle.major, minor: handle.minor, startOffset: startOffset, endOffset: endOffset)
    }

    /// Build a file get request with explicit major/minor handles
    /// Source: FileEncryptedGetRequest.java
    static func buildFileGetRequest(major: UInt8, minor: UInt8, startOffset: UInt32 = 0, endOffset: UInt32 = 0xFFFFFFFF) -> Data {
        var buffer = ByteBuffer(capacity: 11)

        buffer.putUInt8(FossilConstants.Command.fileGet.rawValue)
        buffer.putUInt8(minor)
        buffer.putUInt8(major)
        buffer.putUInt32(startOffset)
        buffer.putUInt32(endOffset)

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
        return buildConfigurationRequest(items: [(.timeConfig, timeData)])
    }
    
    // MARK: - Configuration Request
    
    /// Build a configuration item request
    /// Source: ConfigurationPutRequest.java
    static func buildConfigurationRequest(itemID: FossilConstants.ConfigItemID, data: Data) -> Data {
        buildConfigurationRequest(items: [(itemID, data)])
    }

    static func buildConfigurationRequest(items: [(FossilConstants.ConfigItemID, Data)], fileVersion: UInt16 = 0x0003) -> Data {
        var configPayload = Data()

        for (id, content) in items {
            var itemBuffer = ByteBuffer(capacity: 3 + content.count)
            itemBuffer.putUInt16(UInt16(id.rawValue))
            itemBuffer.putUInt8(UInt8(content.count))
            itemBuffer.putData(content)
            configPayload.append(itemBuffer.data)
        }

        // Return RAW config payload - putFile() handles the file wrapper
        // Source: ConfigurationPutRequest extends FilePutRequest - Gadgetbridge's FilePutRequest wraps the data
        return configPayload
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
    
    // MARK: - Notification Building
    
    /// Build a notification payload for sending to the watch
    /// Source: PlayNotificationRequest.java#L54-L92
    /// https://codeberg.org/Freeyourgadget/Gadgetbridge/.../PlayNotificationRequest.java
    static func buildNotificationPayload(
        type: NotificationType,
        flags: UInt8,
        packageName: String,
        title: String,
        sender: String,
        message: String,
        messageId: UInt32
    ) -> Data {
        // Calculate package CRC
        let packageCrc = CRC32.calculate(data: packageName.data(using: .utf8)!)
        
        return buildNotificationPayload(
            type: type,
            flags: flags,
            packageCrc: packageCrc,
            title: title,
            sender: sender,
            message: message,
            messageId: messageId
        )
    }
    
    /// Build notification payload with explicit CRC (for call notifications)
    /// Source: PlayNotificationRequest.java#L54-L92
    static func buildNotificationPayload(
        type: NotificationType,
        flags: UInt8,
        packageCrc: UInt32,
        title: String,
        sender: String,
        message: String,
        messageId: UInt32
    ) -> Data {
        // Constants from PlayNotificationRequest.java
        let lengthBufferLength: UInt8 = 10
        let uidLength: UInt8 = 4
        let appBundleCRCLength: UInt8 = 4
        
        // Null-terminate strings
        let titleBytes = (title + "\0").data(using: .utf8)!
        let senderBytes = (sender + "\0").data(using: .utf8)!
        
        // Truncate message if too long (max 475 chars)
        var truncatedMessage = message
        if message.count > 475 {
            truncatedMessage = String(message.prefix(475))
        }
        let messageBytes = (truncatedMessage + "\0").data(using: .utf8)!
        
        // Calculate total buffer size
        let mainBufferLength = UInt16(lengthBufferLength) + UInt16(uidLength) + 
                               UInt16(appBundleCRCLength) + UInt16(titleBytes.count) + 
                               UInt16(senderBytes.count) + UInt16(messageBytes.count)
        
        var buffer = ByteBuffer(capacity: Int(mainBufferLength))
        
        // Main buffer length (2 bytes, little-endian)
        buffer.putUInt16(mainBufferLength)
        
        // Length buffer fields
        buffer.putUInt8(lengthBufferLength)
        buffer.putUInt8(type.rawValue)
        buffer.putUInt8(flags)
        buffer.putUInt8(uidLength)
        buffer.putUInt8(appBundleCRCLength)
        buffer.putUInt8(UInt8(titleBytes.count))
        buffer.putUInt8(UInt8(senderBytes.count))
        buffer.putUInt8(UInt8(messageBytes.count))
        
        // Message ID and package CRC (4 bytes each, little-endian)
        buffer.putUInt32(messageId)
        buffer.putUInt32(packageCrc)
        
        // String data (already null-terminated)
        buffer.putData(titleBytes)
        buffer.putData(senderBytes)
        buffer.putData(messageBytes)
        
        return buffer.data
    }
    
    // MARK: - Notification Types
    
    /// Notification type enum matching Gadgetbridge
    /// Source: NotificationType.java
    enum NotificationType: UInt8 {
        case incomingCall = 1
        case text = 2
        case notification = 3
        case dismissNotification = 7
    }
}

// MARK: - Private Helpers

extension RequestBuilder {
    /// Wrap file content with Fossil header and CRC32C checksum
    /// Source: /Users/josh/git/Gadgetbridge/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FilePutRequest.java#L29-L64
    static func buildFilePayload(handle: FileHandle, fileVersion: UInt16, fileData: Data, offset: UInt32 = 0) -> Data {
        var buffer = ByteBuffer(capacity: 12 + fileData.count + 4)
        buffer.putUInt16(handle.rawValue)
        buffer.putUInt16(fileVersion) // SUSPICIOUS: fileVersion should come from SupportedFileVersionsInfo
        if handle == .replyMessages {
            buffer.putBytes([0x00, 0x00, 0x0D, 0x00])
        } else {
            buffer.putUInt32(offset)
        }
        buffer.putUInt32(UInt32(fileData.count))
        buffer.putData(fileData)
        buffer.putUInt32(fileData.crc32c)
        return buffer.data
    }

    private static func nullTerminatedData(for value: String, allowingMaxLength maxLength: Int) -> Data {
        let truncated = String(value.prefix(maxLength))
        var data = truncated.data(using: .utf8) ?? Data()
        data.append(0x00)
        return data
    }
}
