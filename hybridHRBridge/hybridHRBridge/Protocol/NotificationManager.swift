import Foundation
import Combine

/// Manages sending notifications to the watch
/// Implements the notification protocol from Gadgetbridge's PlayNotificationRequest
/// Source: PlayNotificationRequest.java, NotificationType.java
@MainActor
final class NotificationManager: ObservableObject {

    // MARK: - Types

    /// Notification types supported by Fossil HR watches
    /// Source: NotificationType.java#L19-L26
    enum NotificationType: UInt8 {
        case incomingCall = 1
        case text = 2
        case notification = 3
        case email = 4
        case calendar = 5
        case missedCall = 6
        case dismissNotification = 7
    }

    /// Represents a notification to send to the watch
    struct WatchNotification {
        let type: NotificationType
        let title: String
        let sender: String
        let message: String
        let packageName: String
        var flags: UInt8 = 0

        init(type: NotificationType = .notification,
             title: String,
             sender: String = "",
             message: String = "",
             packageName: String = "com.example.app") {
            self.type = type
            self.title = title
            self.sender = sender
            self.message = message
            self.packageName = packageName
        }
    }

    // MARK: - Private Properties

    private let fileTransferManager: FileTransferManager
    private let logger = LogManager.shared

    // MARK: - Initialization

    init(fileTransferManager: FileTransferManager) {
        self.fileTransferManager = fileTransferManager
    }

    // MARK: - Public API

    /// Send a notification to the watch
    /// - Parameter notification: The notification to send
    func sendNotification(_ notification: WatchNotification) async throws {
        let data = buildNotificationPayload(notification)

        logger.info("Notification", "Sending notification: \(notification.title)")
        logger.debug("Notification", "Payload size: \(data.count) bytes")

        try await fileTransferManager.putFile(data, to: .notificationPlay)

        logger.info("Notification", "Notification sent successfully")
    }

    /// Send a simple text notification
    /// - Parameters:
    ///   - title: The notification title (app name)
    ///   - message: The notification message body
    func sendTextNotification(title: String, message: String) async throws {
        let notification = WatchNotification(
            type: .notification,
            title: title,
            sender: "",
            message: message
        )
        try await sendNotification(notification)
    }

    /// Send an incoming call notification
    /// - Parameter caller: The caller name or number
    func sendIncomingCall(caller: String) async throws {
        let notification = WatchNotification(
            type: .incomingCall,
            title: "Phone",
            sender: caller,
            message: "Incoming call"
        )
        try await sendNotification(notification)
    }

    /// Dismiss a notification on the watch
    /// - Parameter notificationId: The ID of the notification to dismiss
    func dismissNotification(id notificationId: Int) async throws {
        // Build dismiss payload
        // Type 7 = DISMISS_NOTIFICATION
        var notification = WatchNotification(
            type: .dismissNotification,
            title: "",
            sender: "",
            message: ""
        )
        let data = buildNotificationPayload(notification, messageId: notificationId)
        try await fileTransferManager.putFile(data, to: .notificationPlay)
        logger.info("Notification", "Dismissed notification: \(notificationId)")
    }

    // MARK: - Private Methods

    /// Build the notification payload according to Fossil protocol
    /// Source: PlayNotificationRequest.java#L54-L92
    private func buildNotificationPayload(_ notification: WatchNotification, messageId: Int? = nil) -> Data {
        let lengthBufferLength: UInt8 = 10
        let uidLength: UInt8 = 4
        let appBundleCRCLength: UInt8 = 4

        // Encode strings as UTF-8 with null terminator
        let titleData = (notification.title + "\0").data(using: .utf8) ?? Data([0])
        let senderData = (notification.sender + "\0").data(using: .utf8) ?? Data([0])

        // Truncate message to 475 characters as per Gadgetbridge
        var messageText = notification.message
        if messageText.count > 475 {
            messageText = String(messageText.prefix(475))
        }
        let messageData = (messageText + "\0").data(using: .utf8) ?? Data([0])

        // Calculate package CRC32
        let packageCRC = notification.packageName.data(using: .utf8)?.crc32 ?? 0

        // Use current timestamp as message ID if not provided
        let msgId = messageId ?? Int(Date().timeIntervalSince1970 * 1000) & 0x7FFFFFFF

        // Calculate total payload length
        let mainBufferLength = Int(lengthBufferLength) + Int(uidLength) + Int(appBundleCRCLength) +
                              titleData.count + senderData.count + messageData.count

        var buffer = ByteBuffer(capacity: mainBufferLength)

        // Write payload length (2 bytes, little-endian)
        buffer.putUInt16(UInt16(mainBufferLength))

        // Write header
        buffer.putUInt8(lengthBufferLength)
        buffer.putUInt8(notification.type.rawValue)
        buffer.putUInt8(notification.flags)
        buffer.putUInt8(uidLength)
        buffer.putUInt8(appBundleCRCLength)
        buffer.putUInt8(UInt8(titleData.count))
        buffer.putUInt8(UInt8(senderData.count))
        buffer.putUInt8(UInt8(messageData.count))

        // Write message ID (4 bytes, little-endian)
        buffer.putUInt32(UInt32(msgId))

        // Write package CRC (4 bytes, little-endian)
        buffer.putUInt32(packageCRC)

        // Write string data
        buffer.putData(titleData)
        buffer.putData(senderData)
        buffer.putData(messageData)

        return buffer.data
    }
}
