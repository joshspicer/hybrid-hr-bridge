import Foundation
import UserNotifications
import Combine

/// Service for intercepting and forwarding iOS notifications to the watch
/// Source: Inspired by Gadgetbridge's FossilHRWatchAdapter.java notification handling
@MainActor
final class NotificationService: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastNotification: NotificationData?
    @Published private(set) var notificationCount: Int = 0
    
    // MARK: - Private Properties
    
    private let logger = LogManager.shared
    private let notificationCenter = UNUserNotificationCenter.current()
    private weak var fileTransferManager: FileTransferManager?
    private var isConfigured = false
    
    // MARK: - Notification Data
    
    struct NotificationData {
        let id: String
        let title: String
        let body: String
        let appIdentifier: String
        let timestamp: Date
        
        var displayText: String {
            if !title.isEmpty && !body.isEmpty {
                return "\(title): \(body)"
            } else if !title.isEmpty {
                return title
            } else {
                return body
            }
        }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        logger.info("NotificationService", "Initialized")
    }
    
    /// Set the file transfer manager for sending notifications to watch
    func setFileTransferManager(_ manager: FileTransferManager) {
        self.fileTransferManager = manager
        logger.info("NotificationService", "File transfer manager set")
    }
    
    // MARK: - Permission Management
    
    /// Request notification permissions from the user
    func requestNotificationPermissions() async {
        logger.info("NotificationService", "Requesting notification permissions")
        
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            
            if granted {
                logger.info("NotificationService", "✅ Notification permissions granted")
                await updatePermissionStatus()
                await setupNotificationDelegate()
            } else {
                logger.warning("NotificationService", "⚠️ Notification permissions denied by user")
                await updatePermissionStatus()
            }
        } catch {
            logger.error("NotificationService", "Failed to request notification permissions: \(error.localizedDescription)")
        }
    }
    
    /// Check current permission status
    func checkPermissionStatus() async {
        await updatePermissionStatus()
    }
    
    private func updatePermissionStatus() async {
        let settings = await notificationCenter.notificationSettings()
        notificationPermissionStatus = settings.authorizationStatus
        
        logger.info("NotificationService", "Permission status: \(statusDescription(settings.authorizationStatus))")
    }
    
    private func statusDescription(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
    
    // MARK: - Notification Delegate Setup
    
    private func setupNotificationDelegate() async {
        logger.info("NotificationService", "Setting up notification delegate")
        notificationCenter.delegate = self
    }
    
    // MARK: - Notification Configuration Upload
    
    /// Configure notification settings on the watch (icons and filters)
    /// This should be called after authentication
    /// Source: FossilHRWatchAdapter.java#L598-L629
    func configureWatchNotifications() async {
        guard let fileTransferManager = fileTransferManager else {
            logger.warning("NotificationService", "Cannot configure notifications - no file transfer manager")
            return
        }
        
        logger.info("NotificationService", "Configuring watch for notifications")
        
        do {
            // Step 1: Upload standard notification icons
            logger.info("NotificationService", "Step 1: Uploading notification icons")
            let icons = NotificationIcon.standardIcons()
            try await fileTransferManager.uploadNotificationIcons(icons)
            
            // Step 2: Upload notification filters
            logger.info("NotificationService", "Step 2: Uploading notification filters")
            let configurations = [
                NotificationConfiguration.generic,
                NotificationConfiguration.call
            ]
            try await fileTransferManager.uploadNotificationFilters(configurations)
            
            isConfigured = true
            logger.info("NotificationService", "✅ Watch configured for notifications successfully")
        } catch {
            logger.error("NotificationService", "Failed to configure watch notifications: \(error.localizedDescription)")
            // Don't set isConfigured to true on failure
        }
    }
    
    // MARK: - Notification Forwarding
    
    /// Forward a notification to the watch
    /// Source: FossilHRWatchAdapter.java#L1388-L1441
    private func forwardNotificationToWatch(_ notification: NotificationData) async {
        guard let fileTransferManager = fileTransferManager else {
            logger.warning("NotificationService", "Cannot forward notification - no file transfer manager")
            return
        }
        
        guard isConfigured else {
            logger.warning("NotificationService", "Cannot forward notification - watch not configured yet")
            return
        }
        
        logger.info("NotificationService", "Forwarding notification to watch")
        logger.debug("NotificationService", "App: \(notification.appIdentifier), Title: \(notification.title)")
        
        do {
            // Send as generic notification (type 3, flags 0x02)
            // Source: PlayTextNotificationRequest.java#L24
            try await fileTransferManager.sendNotification(
                type: .notification,
                flags: 0x02,  // Standard notification flag
                packageName: "generic",  // Use generic for iOS app notifications
                title: notification.title,
                sender: notification.appIdentifier,
                message: notification.body,
                messageId: UInt32(notification.id.hashValue)
            )
            
            logger.info("NotificationService", "✅ Notification forwarded successfully")
        } catch {
            logger.error("NotificationService", "Failed to forward notification: \(error.localizedDescription)")
        }
    }
    
    /// Send a test notification to verify the system is working
    func sendTestNotification() async {
        let testNotification = NotificationData(
            id: UUID().uuidString,
            title: "Test Notification",
            body: "This is a test from Hybrid HR Bridge",
            appIdentifier: "com.hybridhrbridge.test",
            timestamp: Date()
        )
        
        logger.info("NotificationService", "Sending test notification")
        lastNotification = testNotification
        notificationCount += 1
        
        await forwardNotificationToWatch(testNotification)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    
    /// Called when a notification is received while the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            logger.info("NotificationService", "📱 Received foreground notification")
            await handleNotification(notification)
            
            // Show the notification banner even when app is in foreground
            completionHandler([.banner, .sound])
        }
    }
    
    /// Called when the user interacts with a notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            logger.info("NotificationService", "📱 User interacted with notification")
            await handleNotification(response.notification)
            completionHandler()
        }
    }
    
    /// Process a received notification
    private func handleNotification(_ notification: UNNotification) async {
        let content = notification.request.content
        
        // Extract notification data
        let notificationData = NotificationData(
            id: notification.request.identifier,
            title: content.title,
            body: content.body,
            appIdentifier: content.targetContentIdentifier ?? "unknown",
            timestamp: Date()
        )
        
        logger.debug("NotificationService", "Processing notification from: \(notificationData.appIdentifier)")
        logger.debug("NotificationService", "Title: '\(notificationData.title)' Body: '\(notificationData.body)'")
        
        // Update state
        lastNotification = notificationData
        notificationCount += 1
        
        // Forward to watch
        await forwardNotificationToWatch(notificationData)
    }
}
