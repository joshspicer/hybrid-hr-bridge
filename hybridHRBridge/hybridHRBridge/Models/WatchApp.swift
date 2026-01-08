import Foundation

/// Model for watch apps and faces
struct WatchApp: Identifiable, Codable {
    let id: UUID
    var name: String
    var version: String
    var appType: WatchAppType
    var installedDate: Date?
    var fileSize: Int?
    var iconData: Data?
    
    /// Path to the .wapp file (if local)
    var filePath: URL?
    
    init(name: String, version: String, appType: WatchAppType) {
        self.id = UUID()
        self.name = name
        self.version = version
        self.appType = appType
    }
}

/// Type of watch app
enum WatchAppType: Int, Codable {
    case watchFace = 1
    case app = 2
    
    var displayName: String {
        switch self {
        case .watchFace: return "Watch Face"
        case .app: return "App"
        }
    }
}

/// Complication (widget) on a watch face
struct WatchComplication: Identifiable, Codable {
    let id: UUID
    var position: ComplicationPosition
    var type: ComplicationType
    var config: [String: String]
    
    init(position: ComplicationPosition, type: ComplicationType) {
        self.id = UUID()
        self.position = position
        self.type = type
        self.config = [:]
    }
}

/// Position of complication on watch face
enum ComplicationPosition: String, Codable, CaseIterable {
    case topLeft = "top_left"
    case topRight = "top_right"
    case bottomLeft = "bottom_left"
    case bottomRight = "bottom_right"
    case center = "center"
    
    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .center: return "Center"
        }
    }
}

/// Type of complication data
enum ComplicationType: String, Codable, CaseIterable {
    case time = "time"
    case date = "date"
    case steps = "steps"
    case heartRate = "heart_rate"
    case battery = "battery"
    case weather = "weather"
    case calories = "calories"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .time: return "Time"
        case .date: return "Date"
        case .steps: return "Steps"
        case .heartRate: return "Heart Rate"
        case .battery: return "Battery"
        case .weather: return "Weather"
        case .calories: return "Calories"
        case .custom: return "Custom"
        }
    }
}
