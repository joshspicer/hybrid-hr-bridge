import Foundation

/// Watch device model
struct WatchDevice: Identifiable, Codable {
    let id: UUID
    var name: String
    var secretKey: String?
    var lastConnected: Date?
    var firmwareVersion: String?
    var batteryLevel: Int?
    var batteryVoltageMillivolts: Int?
    
    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Connection status for display
enum WatchConnectionStatus {
    case disconnected
    case scanning
    case connecting
    case authenticating
    case connected
    
    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .authenticating: return "Authenticating..."
        case .connected: return "Connected"
        }
    }
    
    var isConnected: Bool {
        self == .connected
    }
}
