import Foundation

/// Model for watch notifications
struct WatchNotification: Identifiable {
    let id: UUID
    let type: NotificationType
    let title: String
    let sender: String
    let message: String
    let appIdentifier: String
    let timestamp: Date
    
    init(
        type: NotificationType,
        title: String,
        sender: String,
        message: String,
        appIdentifier: String
    ) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.sender = sender
        self.message = message
        self.appIdentifier = appIdentifier
        self.timestamp = Date()
    }
}

/// Notification configuration for an app
struct NotificationConfig: Identifiable, Codable {
    let id: UUID
    var appIdentifier: String
    var displayName: String
    var enabled: Bool
    var priority: NotificationPriority
    var vibrationPattern: VibrationPattern
    var iconName: String?
    
    init(appIdentifier: String, displayName: String) {
        self.id = UUID()
        self.appIdentifier = appIdentifier
        self.displayName = displayName
        self.enabled = true
        self.priority = .normal
        self.vibrationPattern = .short
        self.iconName = nil
    }
}

/// Notification priority levels
enum NotificationPriority: Int, Codable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}

/// Vibration patterns for notifications
enum VibrationPattern: Int, Codable, CaseIterable {
    case none = 0
    case short = 1
    case medium = 2
    case long = 3
    case double = 4
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .short: return "Short"
        case .medium: return "Medium"
        case .long: return "Long"
        case .double: return "Double"
        }
    }
}
