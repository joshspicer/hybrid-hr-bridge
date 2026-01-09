import Foundation
import CoreBluetooth
import Combine

/// Manages Bluetooth Low Energy communication with Fossil Hybrid HR watches
/// Handles device discovery, connection, and characteristic read/write operations
@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var connectedDevice: ConnectedDevice?
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var lastError: BluetoothError?
    
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
    
    struct DiscoveredDevice: Identifiable, Equatable {
        let id: UUID
        let peripheral: CBPeripheral
        let name: String
        let rssi: Int
        var lastSeen: Date
        
        static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    struct ConnectedDevice {
        let peripheral: CBPeripheral
        let name: String
        var characteristics: [CBUUID: CBCharacteristic] = [:]
        
        var isReady: Bool {
            // Check we have all required characteristics
            FossilConstants.allCharacteristics.allSatisfy { characteristics[$0] != nil }
        }
    }
    
    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var pendingConnection: CBPeripheral?
    private var characteristicUpdateHandlers: [CBUUID: (Data) -> Void] = [:]
    private var writeCompletionHandler: ((Error?) -> Void)?
    private let logger = LogManager.shared
    
    // MARK: - Initialization

    override init() {
        super.init()
        // Use nil queue to run on the main queue, which is required since this class is @MainActor
        // This prevents crashes on iOS 18+ where actor isolation is more strictly enforced
        centralManager = CBCentralManager(delegate: self, queue: nil)

        // Log initialization after the actor context is established
        Task { @MainActor in
            logger.info("BLE", "BluetoothManager initialized")
            logger.debug("BLE", "CBCentralManager created with main queue")
        }
    }
    
    // MARK: - Public API
    
    /// Start scanning for Fossil Hybrid HR watches
    func startScanning() {
        logger.info("BLE", "Starting scan for Fossil Hybrid HR watches")

        guard centralManager.state == .poweredOn else {
            logger.error("BLE", "Cannot scan - Bluetooth not powered on (state: \(centralManager.state.rawValue))")
            lastError = .bluetoothNotAvailable
            return
        }

        discoveredDevices.removeAll()
        isScanning = true
        connectionState = .scanning

        logger.debug("BLE", "Scanning for service UUID: \(FossilConstants.serviceUUID.uuidString)")

        centralManager.scanForPeripherals(
            withServices: [FossilConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        logger.info("BLE", "Scan started successfully")
    }
    
    /// Stop scanning for devices
    func stopScanning() {
        logger.info("BLE", "Stopping scan")
        centralManager.stopScan()
        isScanning = false
        if connectionState == .scanning {
            connectionState = .disconnected
        }
        logger.debug("BLE", "Scan stopped, state: \(connectionState)")
    }
    
    /// Connect to a discovered device
    func connect(to device: DiscoveredDevice) {
        logger.info("BLE", "Initiating connection to \(device.name) (ID: \(device.id))")
        logger.debug("BLE", "RSSI: \(device.rssi) dBm, Last seen: \(device.lastSeen)")

        stopScanning()
        connectionState = .connecting
        pendingConnection = device.peripheral
        device.peripheral.delegate = self

        centralManager.connect(device.peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])

        logger.debug("BLE", "Connection request sent to CoreBluetooth")
    }

    /// Connect to a device by UUID (useful for reconnecting to saved devices)
    func connect(toDeviceWithUUID uuid: UUID) {
        logger.info("BLE", "Attempting to connect to device with UUID: \(uuid)")

        guard centralManager.state == .poweredOn else {
            logger.error("BLE", "Cannot connect - Bluetooth not powered on")
            lastError = .bluetoothNotAvailable
            return
        }

        // Try to retrieve the peripheral from CoreBluetooth
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])

        guard let peripheral = peripherals.first else {
            logger.warning("BLE", "Peripheral with UUID \(uuid) not found - starting scan")
            // If we can't retrieve it, we need to scan for it first
            lastError = .deviceNotFound
            startScanning()
            return
        }

        logger.info("BLE", "Found peripheral: \(peripheral.name ?? "Unknown")")
        stopScanning()
        connectionState = .connecting
        pendingConnection = peripheral
        peripheral.delegate = self

        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])

        logger.debug("BLE", "Connection request sent to CoreBluetooth for saved device")
    }
    
    /// Disconnect from the current device
    func disconnect() {
        guard let device = connectedDevice else {
            logger.warning("BLE", "Disconnect called but no device connected")
            return
        }
        logger.info("BLE", "Disconnecting from \(device.name)")
        connectionState = .disconnecting
        centralManager.cancelPeripheralConnection(device.peripheral)
    }
    
    /// Write data to a characteristic
    func write(data: Data, to characteristic: CBUUID, type: CBCharacteristicWriteType = .withResponse) async throws {
        logger.debug("BLE", "Writing \(data.count) bytes to characteristic \(characteristic.uuidString)")
        logger.debug("BLE", "Data: \(data.hexString)")
        logger.debug("BLE", "Write type: \(type == .withResponse ? "withResponse" : "withoutResponse")")

        guard let device = connectedDevice,
              let char = device.characteristics[characteristic] else {
            logger.error("BLE", "Characteristic \(characteristic.uuidString) not found")
            throw BluetoothError.characteristicNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            if type == .withResponse {
                writeCompletionHandler = { error in
                    if let error = error {
                        self.logger.error("BLE", "Write failed: \(error.localizedDescription)")
                        continuation.resume(throwing: BluetoothError.writeFailed(error))
                    } else {
                        self.logger.debug("BLE", "Write completed successfully")
                        continuation.resume()
                    }
                }
            }

            device.peripheral.writeValue(data, for: char, type: type)

            if type == .withoutResponse {
                logger.debug("BLE", "Write without response completed")
                continuation.resume()
            }
        }
    }
    
    /// Register a handler for characteristic notifications
    func registerNotificationHandler(for characteristic: CBUUID, handler: @escaping (Data) -> Void) {
        logger.debug("BLE", "Registering notification handler for \(characteristic.uuidString)")
        characteristicUpdateHandlers[characteristic] = handler
    }

    /// Enable notifications for a characteristic
    func enableNotifications(for characteristic: CBUUID) async throws {
        logger.info("BLE", "Enabling notifications for \(characteristic.uuidString)")

        guard let device = connectedDevice,
              let char = device.characteristics[characteristic] else {
            logger.error("BLE", "Characteristic \(characteristic.uuidString) not found for notifications")
            throw BluetoothError.characteristicNotFound
        }

        device.peripheral.setNotifyValue(true, for: char)
        logger.debug("BLE", "Notification enable request sent")
    }
    
    /// Request a larger MTU for efficient transfers
    func requestMTU(_ mtu: Int) {
        // Note: iOS negotiates MTU automatically, but we can check the maximum
        // write length for the characteristic
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            logger.info("BLE", "Bluetooth state changed to: \(central.state.rawValue)")

            switch central.state {
            case .poweredOn:
                logger.info("BLE", "✅ Bluetooth powered on and ready")
            case .poweredOff:
                logger.warning("BLE", "⚠️ Bluetooth powered off")
                lastError = .bluetoothPoweredOff
                connectionState = .disconnected
            case .unauthorized:
                logger.error("BLE", "❌ Bluetooth unauthorized - check app permissions")
                lastError = .bluetoothUnauthorized
            case .unsupported:
                logger.error("BLE", "❌ Bluetooth unsupported on this device")
                lastError = .bluetoothUnsupported
            case .resetting:
                logger.warning("BLE", "⚠️ Bluetooth is resetting")
            case .unknown:
                logger.debug("BLE", "Bluetooth state unknown")
            @unknown default:
                logger.warning("BLE", "Unknown Bluetooth state: \(central.state.rawValue)")
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"

            if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                // Update existing device
                discoveredDevices[index].lastSeen = Date()
                logger.debug("BLE", "Updated device: \(name) (RSSI: \(RSSI))")
            } else {
                // Add new device
                let device = DiscoveredDevice(
                    id: peripheral.identifier,
                    peripheral: peripheral,
                    name: name,
                    rssi: RSSI.intValue,
                    lastSeen: Date()
                )
                discoveredDevices.append(device)
                logger.info("BLE", "📱 Discovered: \(name) (RSSI: \(RSSI), ID: \(peripheral.identifier))")
                logger.debug("BLE", "Advertisement data: \(advertisementData)")
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            logger.info("BLE", "✅ Connected to \(peripheral.name ?? "Unknown") (ID: \(peripheral.identifier))")
            connectionState = .discovering
            connectedDevice = ConnectedDevice(
                peripheral: peripheral,
                name: peripheral.name ?? "Fossil Watch"
            )

            logger.info("BLE", "Starting service discovery...")
            logger.debug("BLE", "Looking for service UUID: \(FossilConstants.serviceUUID.uuidString)")
            // Discover services
            peripheral.discoverServices([FossilConstants.serviceUUID])
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            logger.error("BLE", "❌ Failed to connect to \(peripheral.name ?? "Unknown")")
            if let error = error {
                logger.error("BLE", "Connection error: \(error.localizedDescription)")
                logger.debug("BLE", "Error details: \(error)")
            }
            lastError = .connectionFailed(error)
            connectionState = .disconnected
            pendingConnection = nil
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            logger.info("BLE", "Disconnected from \(peripheral.name ?? "Unknown")")
            if let error = error {
                logger.warning("BLE", "Disconnection was unexpected: \(error.localizedDescription)")
                logger.debug("BLE", "Disconnect error details: \(error)")
                lastError = .disconnected(error)
            } else {
                logger.info("BLE", "Clean disconnection")
            }

            connectedDevice = nil
            connectionState = .disconnected
            characteristicUpdateHandlers.removeAll()
            logger.debug("BLE", "Cleared \(characteristicUpdateHandlers.count) notification handlers")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error = error {
                logger.error("BLE", "Service discovery failed: \(error.localizedDescription)")
                logger.debug("BLE", "Service discovery error details: \(error)")
                lastError = .serviceDiscoveryFailed(error)
                return
            }

            guard let services = peripheral.services else {
                logger.warning("BLE", "No services discovered")
                return
            }

            logger.info("BLE", "Discovered \(services.count) service(s)")

            for service in services {
                logger.info("BLE", "Service found: \(service.uuid.uuidString)")
                if service.uuid == FossilConstants.serviceUUID {
                    logger.info("BLE", "Found Fossil service! Discovering characteristics...")
                    logger.debug("BLE", "Looking for \(FossilConstants.allCharacteristics.count) characteristics")
                    peripheral.discoverCharacteristics(FossilConstants.allCharacteristics, for: service)
                }
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error = error {
                logger.error("BLE", "Characteristic discovery failed: \(error.localizedDescription)")
                logger.debug("BLE", "Characteristic discovery error details: \(error)")
                lastError = .characteristicDiscoveryFailed(error)
                return
            }

            guard let characteristics = service.characteristics else {
                logger.warning("BLE", "No characteristics discovered for service \(service.uuid.uuidString)")
                return
            }

            logger.info("BLE", "Discovered \(characteristics.count) characteristic(s) for service \(service.uuid.uuidString)")

            for characteristic in characteristics {
                logger.info("BLE", "Characteristic: \(characteristic.uuid.uuidString)")
                logger.debug("BLE", "  Properties: \(characteristic.properties)")
                connectedDevice?.characteristics[characteristic.uuid] = characteristic

                // Enable notifications for characteristics that support it
                if characteristic.properties.contains(.notify) {
                    logger.debug("BLE", "  Enabling notifications for \(characteristic.uuid.uuidString)")
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }

            // Check if we have all characteristics
            if connectedDevice?.isReady == true {
                logger.info("BLE", "✅ All required characteristics discovered - device ready!")
                let charList = connectedDevice?.characteristics.keys.map { $0.uuidString }.joined(separator: ", ") ?? ""
                logger.debug("BLE", "Available characteristics: \(charList)")
                connectionState = .authenticating
                // Authentication will be handled by AuthenticationManager
            } else {
                let missing = FossilConstants.allCharacteristics.filter { connectedDevice?.characteristics[$0] == nil }
                logger.warning("BLE", "Still missing \(missing.count) required characteristic(s)")
                logger.debug("BLE", "Missing: \(missing.map { $0.uuidString }.joined(separator: ", "))")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                logger.error("BLE", "Characteristic read error for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
                return
            }

            guard let data = characteristic.value else {
                logger.warning("BLE", "No data in characteristic update for \(characteristic.uuid.uuidString)")
                return
            }

            logger.debug("BLE", "📨 Received \(data.count) bytes from \(characteristic.uuid.uuidString)")
            logger.debug("BLE", "Data: \(data.hexString)")

            // Call registered handler
            if let handler = characteristicUpdateHandlers[characteristic.uuid] {
                handler(data)
            } else {
                logger.warning("BLE", "No handler registered for \(characteristic.uuid.uuidString)")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                logger.error("BLE", "Write failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
                logger.debug("BLE", "Write error details: \(error)")
            } else {
                logger.debug("BLE", "✅ Write successful to \(characteristic.uuid.uuidString)")
            }

            writeCompletionHandler?(error)
            writeCompletionHandler = nil
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                logger.error("BLE", "Notification state update failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
                logger.debug("BLE", "Notification error details: \(error)")
            } else {
                let state = characteristic.isNotifying ? "enabled" : "disabled"
                logger.info("BLE", "Notifications \(state) for \(characteristic.uuid.uuidString)")
            }
        }
    }
}

// MARK: - Errors

enum BluetoothError: Error, LocalizedError {
    case bluetoothNotAvailable
    case bluetoothPoweredOff
    case bluetoothUnauthorized
    case bluetoothUnsupported
    case connectionFailed(Error?)
    case disconnected(Error?)
    case serviceDiscoveryFailed(Error)
    case characteristicDiscoveryFailed(Error)
    case characteristicNotFound
    case writeFailed(Error)
    case timeout
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .bluetoothNotAvailable:
            return "Bluetooth is not available"
        case .bluetoothPoweredOff:
            return "Please turn on Bluetooth"
        case .bluetoothUnauthorized:
            return "Bluetooth access not authorized"
        case .bluetoothUnsupported:
            return "Bluetooth is not supported on this device"
        case .connectionFailed(let error):
            return "Connection failed: \(error?.localizedDescription ?? "Unknown error")"
        case .disconnected(let error):
            return "Disconnected: \(error?.localizedDescription ?? "Unknown reason")"
        case .serviceDiscoveryFailed(let error):
            return "Service discovery failed: \(error.localizedDescription)"
        case .characteristicDiscoveryFailed(let error):
            return "Characteristic discovery failed: \(error.localizedDescription)"
        case .characteristicNotFound:
            return "Required characteristic not found"
        case .writeFailed(let error):
            return "Write failed: \(error.localizedDescription)"
        case .timeout:
            return "Operation timed out"
        case .deviceNotFound:
            return "Device not found - scanning..."
        }
    }
}
