import Foundation
import CoreBluetooth

/// Handles Bluetooth device connection management and state
@MainActor
final class ConnectionManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var connectedDevice: ConnectedDevice?
    @Published private(set) var connectionState: ConnectionState = .disconnected
    
    /// Whether the connected peripheral is authorized to receive ANCS notifications
    /// User must enable "Share System Notifications" in iOS Bluetooth settings for this to be true
    @Published private(set) var ancsAuthorized = false
    
    // MARK: - Types
    
    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting
        case discovering
        case authenticating
        case connected
        case disconnecting
    }
    
    struct ConnectedDevice {
        let peripheral: CBPeripheral
        let name: String
        var characteristics: [CBUUID: CBCharacteristic] = [:]
        var notificationsEnabled: Set<CBUUID> = []
        
        var isReady: Bool {
            // Check we have all required characteristics
            FossilConstants.allCharacteristics.allSatisfy { characteristics[$0] != nil }
        }
        
        /// Returns true when all characteristics that support notifications/indications have them enabled
        var isNotificationsReady: Bool {
            guard isReady else { return false }
            // Check if all indication/notify characteristics have confirmed notification state
            for uuid in FossilConstants.allCharacteristics {
                guard let char = characteristics[uuid] else { return false }
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    if !notificationsEnabled.contains(uuid) {
                        return false
                    }
                }
            }
            return true
        }
    }
    
    // MARK: - Private Properties
    
    private let logger = LogManager.shared
    private weak var centralManager: CBCentralManager?
    private(set) var pendingConnection: CBPeripheral?
    private var hasTransitionedToAuthenticating = false
    
    // MARK: - Initialization
    
    init() {}
    
    func setCentralManager(_ manager: CBCentralManager) {
        self.centralManager = manager
    }
    
    // MARK: - Public API
    
    /// Connect to a discovered device
    func connect(to peripheral: CBPeripheral, delegate: CBPeripheralDelegate) {
        guard let centralManager = centralManager else {
            logger.error("Connection", "Central manager not set")
            return
        }
        
        connectionState = .connecting
        pendingConnection = peripheral
        peripheral.delegate = delegate
        
        // CBConnectPeripheralOptionRequiresANCS tells iOS this connection needs ANCS access
        // On first connection, iOS will prompt user to "Share System Notifications"
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionRequiresANCS: true
        ])
        
        logger.info("Connection", "Connecting to \(peripheral.name ?? "Unknown") with ANCS requirement...")
    }
    
    /// Disconnect from the current device
    func disconnect() {
        guard let centralManager = centralManager else { return }
        guard let device = connectedDevice else { return }
        
        connectionState = .disconnecting
        centralManager.cancelPeripheralConnection(device.peripheral)
        logger.info("Connection", "Disconnecting...")
    }
    
    /// Handle successful connection
    func handleDidConnect(_ peripheral: CBPeripheral) {
        logger.info("Connection", "✅ Connected to \(peripheral.name ?? "Unknown")")
        connectionState = .discovering
        
        // Check ANCS authorization status
        #if canImport(CoreBluetooth)
        ancsAuthorized = peripheral.ancsAuthorized
        logger.info("Connection", "ANCS authorized: \(ancsAuthorized ? "YES ✅" : "NO ❌")")
        if !ancsAuthorized {
            logger.info("Connection", "To receive system notifications, enable 'Share System Notifications' in iOS Settings > Bluetooth > [watch] > (i)")
        }
        #endif
        
        // Create connected device
        connectedDevice = ConnectedDevice(
            peripheral: peripheral,
            name: peripheral.name ?? "Unknown Device"
        )
        
        // Discover services
        peripheral.discoverServices([FossilConstants.serviceUUID])
    }
    
    /// Handle disconnection
    func handleDidDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            logger.error("Connection", "Disconnected with error: \(error.localizedDescription)")
        } else {
            logger.info("Connection", "Disconnected")
        }
        
        connectedDevice = nil
        connectionState = .disconnected
        pendingConnection = nil
        hasTransitionedToAuthenticating = false
        ancsAuthorized = false
    }
    
    /// Handle failed connection
    func handleDidFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            logger.error("Connection", "Failed to connect: \(error.localizedDescription)")
        } else {
            logger.error("Connection", "Failed to connect")
        }
        
        connectionState = .disconnected
        pendingConnection = nil
        hasTransitionedToAuthenticating = false
    }
    
    /// Store discovered characteristic
    func storeCharacteristic(_ characteristic: CBCharacteristic) {
        connectedDevice?.characteristics[characteristic.uuid] = characteristic
        logger.debug("Connection", "Stored characteristic: \(characteristic.uuid)")
    }
    
    /// Mark notification as enabled for a characteristic
    func markNotificationEnabled(for characteristic: CBCharacteristic) {
        connectedDevice?.notificationsEnabled.insert(characteristic.uuid)
        
        // Log notification progress
        if let device = connectedDevice {
            let enabledCount = device.notificationsEnabled.count
            let totalRequired = FossilConstants.allCharacteristics.filter { uuid in
                if let char = device.characteristics[uuid] {
                    return char.properties.contains(.notify) || char.properties.contains(.indicate)
                }
                return false
            }.count
            
            logger.debug("Connection", "Notification progress: \(enabledCount)/\(totalRequired) characteristics ready")
            
            // Check if we're now fully ready
            if !hasTransitionedToAuthenticating && device.isNotificationsReady {
                hasTransitionedToAuthenticating = true
                logger.info("Connection", "🎉 All notifications enabled! Device ready for authentication")
                connectionState = .authenticating
            }
        }
    }
    
    /// Update connection state
    func updateState(_ state: ConnectionState) {
        connectionState = state
    }
    
    /// Get characteristic by UUID
    func getCharacteristic(_ uuid: CBUUID) -> CBCharacteristic? {
        return connectedDevice?.characteristics[uuid]
    }
    
    /// Check if device is ready
    var isDeviceReady: Bool {
        connectedDevice?.isReady ?? false
    }
}
