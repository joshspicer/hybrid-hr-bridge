import Foundation
import CoreBluetooth

/// BLE UUIDs and constants for Fossil Hybrid HR communication
/// Reference: https://codeberg.org/Freeyourgadget/Gadgetbridge
enum FossilConstants {
    
    // MARK: - Service UUIDs
    
    /// Main Fossil Hybrid HR service UUID
    /// Source: QHybridCoordinator.java#L64-L80
    static let serviceUUID = CBUUID(string: "3dda0001-957f-7d4a-34a6-74696673696d")
    
    // MARK: - Characteristic UUIDs
    
    /// Connection parameters / device pairing / control
    /// Source: Request.java#L53, CheckDevicePairingRequest.java
    static let characteristicConnectionParams = CBUUID(string: "3dda0002-957f-7d4a-34a6-74696673696d")
    
    /// Alias for device control/pairing operations
    static let characteristicControl = characteristicConnectionParams
    
    /// File operations (put/get requests)
    /// Source: FilePutRawRequest.java#L237
    static let characteristicFileOperations = CBUUID(string: "3dda0003-957f-7d4a-34a6-74696673696d")
    
    /// File data transfer
    /// Source: FileEncryptedPutRequest.java#L89-L107
    static let characteristicFileData = CBUUID(string: "3dda0004-957f-7d4a-34a6-74696673696d")
    
    /// Authentication
    /// Source: AuthenticationRequest.java#L22-L28
    static let characteristicAuthentication = CBUUID(string: "3dda0005-957f-7d4a-34a6-74696673696d")
    
    /// Background events (button presses, etc.)
    /// Source: FossilWatchAdapter.java#L641-L652
    static let characteristicEvents = CBUUID(string: "3dda0006-957f-7d4a-34a6-74696673696d")
    
    /// Standard BLE Heart Rate Measurement
    /// Source: FossilWatchAdapter.java#L649
    static let characteristicHeartRate = CBUUID(string: "00002a37-0000-1000-8000-00805f9b34fb")
    
    /// All characteristics to discover
    static let allCharacteristics: [CBUUID] = [
        characteristicConnectionParams,
        characteristicFileOperations,
        characteristicFileData,
        characteristicAuthentication,
        characteristicEvents
    ]
    
    // MARK: - Connection Parameters
    
    /// Default connection parameters request
    /// Source: SetConnectionParametersRequest.java#L44-L46
    static let connectionParametersPayload: [UInt8] = [
        0x02, 0x09,       // Command
        0x0C, 0x00,       // Connection interval min: 12 * 1.25ms = 15ms
        0x0C, 0x00,       // Connection interval max: 12 * 1.25ms = 15ms
        0x2D, 0x00,       // Slave latency: 45
        0x58, 0x02        // Supervision timeout: 600 * 10ms = 6s
    ]
    
    // MARK: - Protocol Commands
    
    enum Command: UInt8 {
        case fileGet = 0x01
        case fileVerify = 0x02
        case filePut = 0x03
        case fileClose = 0x04
    }
    
    // MARK: - Response Types
    
    /// Source: FileVerifyRequest.java#L45-L69
    enum ResponseType: UInt8 {
        case fileGetInit = 0x01
        case filePutInit = 0x03
        case fileComplete = 0x04
        case dataAck = 0x08
        case continuation = 0x0A
    }
    
    // MARK: - Result Codes
    
    /// Source: ResultCode.java#L40-L71
    enum ResultCode: UInt8 {
        case success = 0
        case inputDataInvalid = 139
        case notAuthenticated = 140
        case sizeOverLimit = 141
        
        var isSuccess: Bool { self == .success }
    }
    
    // MARK: - Configuration Item IDs
    
    /// Source: ConfigurationPutRequest.java#L32-L45
    enum ConfigItemID: UInt8 {
        case currentStepCount = 0x02
        case dailyStepGoal = 0x03
        case inactivityWarning = 0x09
        case vibrationStrength = 0x0A
        case timeConfig = 0x0C
        case batteryConfig = 0x0D
        case heartRateMode = 0x0E
        case unitsConfig = 0x10
        case timezoneOffset = 0x11
        case fitnessConfig = 0x14
    }
}
