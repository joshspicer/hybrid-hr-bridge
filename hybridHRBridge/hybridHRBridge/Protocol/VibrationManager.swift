import Foundation
import Combine

/// Manages sending vibration commands to the watch
/// Implements logic from Gadgetbridge's PlayNotificationRequest
/// Source: PlayNotificationRequest.java
@MainActor
final class VibrationManager: ObservableObject {
    
    // MARK: - Types
    
    enum VibrationType: UInt8 {
        case singleShort = 3
        case doubleShort = 2
        case tripleShort = 1
        case singleNormal = 5
        case doubleNormal = 6
        case tripleNormal = 7
        case singleLong = 8
        case noVibration = 9
    }
    
    // MARK: - Private Properties
    
    private let bluetoothManager: BluetoothManager
    private let logger = LogManager.shared
    
    // MARK: - Initialization
    
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }
    
    // MARK: - Public API
    
    /// Send a vibration command to the watch
    /// - Parameter type: The type of vibration pattern
    func sendVibration(_ type: VibrationType) async throws {
        // Construct command based on PlayNotificationRequest logic
        // Header: [0x02, 0x07, 0x15, 0x10, 0x01]
        // Payload: [Type, 0x05, 0x02, 0x00, 0x00] (length=0, no hands moving)
        
        // Gadgetbridge constructs it as:
        // Header: 2, 7, 15, 10, 1
        // Payload:
        //   [0]: Vibration Type
        //   [1]: 5
        //   [2]: Length * 2 + 2 (Length is number of hands moving, here 0, so 2)
        //   [3-4]: Short 0
        
        let header = Data([0x02, 0x07, 0x15, 0x10, 0x01])
        let payload = Data([type.rawValue, 0x05, 0x02, 0x00, 0x00])
        
        let command = header + payload
        
        logger.info("Protocol", "Sending vibration command: \(type)")
        logger.debug("Protocol", "Command data: \(command.hexString)")
        
        try await bluetoothManager.write(
            data: command,
            to: FossilConstants.characteristicControl
        )
    }
}
