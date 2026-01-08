import Foundation

/// File handles for Fossil Hybrid HR data transfers
/// Each handle represents a different type of data on the watch
/// Source: FileHandle.java#L19-L45
/// https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FileHandle.java
enum FileHandle: UInt16 {
    /// Firmware updates
    case otaFile = 0x0000
    
    /// Activity/fitness data
    case activityFile = 0x0100
    
    /// Hardware debug logs
    case hardwareLogFile = 0x0200
    
    /// Font files
    case fontFile = 0x0300
    
    /// Music control data
    case musicInfo = 0x0400
    
    /// UI state control
    case uiControl = 0x0500
    
    /// Button/hand actions configuration
    case handActions = 0x0600
    
    /// Watchface background images
    case assetBackgroundImages = 0x0700
    
    /// Notification icons
    case assetNotificationImages = 0x0701
    
    /// Localization/translation strings
    case assetTranslations = 0x0702
    
    /// Quick reply images
    case assetReplyImages = 0x0703
    
    /// Device configuration
    case configuration = 0x0800
    
    /// Push notifications to watch
    case notificationPlay = 0x0900
    
    /// Alarm settings
    case alarms = 0x0A00
    
    /// Device information
    case deviceInfo = 0x0B00
    
    /// Notification filter/routing
    case notificationFilter = 0x0C00
    
    /// Watch parameters
    case watchParameters = 0x0E00
    
    /// Lookup tables
    case lookUpTable = 0x0F00
    
    /// Heart rate data
    case rate = 0x1000
    
    /// Quick reply messages
    case replyMessages = 0x1300
    
    /// Watch apps and faces
    case appCode = 0x15FE
    
    // MARK: - Computed Properties
    
    /// Major handle component (high byte)
    var major: UInt8 {
        UInt8((rawValue >> 8) & 0xFF)
    }
    
    /// Minor handle component (low byte)
    var minor: UInt8 {
        UInt8(rawValue & 0xFF)
    }
    
    /// Handle as little-endian bytes for protocol
    var bytes: [UInt8] {
        [minor, major]  // Little-endian: minor first
    }
    
    // MARK: - Initialization
    
    /// Create handle from major/minor components
    init(major: UInt8, minor: UInt8) {
        let value = (UInt16(major) << 8) | UInt16(minor)
        self = FileHandle(rawValue: value) ?? .otaFile
    }
}

// MARK: - CustomStringConvertible

extension FileHandle: CustomStringConvertible {
    var description: String {
        switch self {
        case .otaFile: return "OTA_FILE"
        case .activityFile: return "ACTIVITY_FILE"
        case .hardwareLogFile: return "HARDWARE_LOG_FILE"
        case .fontFile: return "FONT_FILE"
        case .musicInfo: return "MUSIC_INFO"
        case .uiControl: return "UI_CONTROL"
        case .handActions: return "HAND_ACTIONS"
        case .assetBackgroundImages: return "ASSET_BACKGROUND_IMAGES"
        case .assetNotificationImages: return "ASSET_NOTIFICATION_IMAGES"
        case .assetTranslations: return "ASSET_TRANSLATIONS"
        case .assetReplyImages: return "ASSET_REPLY_IMAGES"
        case .configuration: return "CONFIGURATION"
        case .notificationPlay: return "NOTIFICATION_PLAY"
        case .alarms: return "ALARMS"
        case .deviceInfo: return "DEVICE_INFO"
        case .notificationFilter: return "NOTIFICATION_FILTER"
        case .watchParameters: return "WATCH_PARAMETERS"
        case .lookUpTable: return "LOOK_UP_TABLE"
        case .rate: return "RATE"
        case .replyMessages: return "REPLY_MESSAGES"
        case .appCode: return "APP_CODE"
        }
    }
}
