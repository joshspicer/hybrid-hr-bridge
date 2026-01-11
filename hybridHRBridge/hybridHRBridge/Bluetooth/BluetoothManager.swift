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
    private var centralManager: CBCentralManager!
    private var pendingConnection: CBPeripheral?
    private var characteristicUpdateHandlers: [CBUUID: (Data) -> Void] = [:]
    private var writeCompletions: [CBUUID: (Error?) -> Void] = [:]  // Track writes per characteristic
    private var hasTransitionedToAuthenticating = false  // Prevent duplicate authentication triggers
    
    // MARK: - Computed Properties
    
    /// Exposes the CoreBluetooth manager state for UI display
    var bluetoothState: CBManagerState {
        centralManager.state
    }
    
    // MARK: - Initialization

    override init() {
        super.init()
        // Use nil queue to run on the main queue, which is required since this class is @MainActor
        // This prevents crashes on iOS 18+ where actor isolation is more strictly enforced
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public API
    
    /// Start scanning for Fossil Hybrid HR watches
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            lastError = .bluetoothNotAvailable
            return
        }
        
        discoveredDevices.removeAll()
        isScanning = true
        connectionState = .scanning
        
        centralManager.scanForPeripherals(
            withServices: [FossilConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        print("[BLE] Started scanning for Fossil devices")
    }
    
    /// Stop scanning for devices
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        if connectionState == .scanning {
            connectionState = .disconnected
        }
        print("[BLE] Stopped scanning")
    }
    
    /// Connect to a discovered device
    func connect(to device: DiscoveredDevice) {
        stopScanning()
        connectionState = .connecting
        pendingConnection = device.peripheral
        device.peripheral.delegate = self
        
        // CBConnectPeripheralOptionRequiresANCS tells iOS this connection needs ANCS access
        // On first connection, iOS will prompt user to "Share System Notifications"
        // This is required for the watch to receive iOS notifications via ANCS
        centralManager.connect(device.peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionRequiresANCS: true
        ])
        
        logger.info("BLE", "Connecting to \(device.name) with ANCS requirement...")
        print("[BLE] Connecting to \(device.name)...")
    }
    
    /// Connect to a previously known device by UUID
    /// Used for reconnecting to saved devices
    func connect(toDeviceWithUUID uuid: UUID) {
        stopScanning()
        connectionState = .connecting
        
        // Try to retrieve the peripheral from Core Bluetooth's cache
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        
        if let peripheral = peripherals.first {
            print("[BLE] Found cached peripheral for UUID \(uuid), connecting...")
            logger.info("BLE", "Found cached peripheral, connecting with ANCS requirement...")
            pendingConnection = peripheral
            peripheral.delegate = self
            
            centralManager.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionRequiresANCS: true
            ])
        } else {
            // Peripheral not in cache, try to find it via connected peripherals with our service
            let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [FossilConstants.serviceUUID])
            
            if let peripheral = connectedPeripherals.first(where: { $0.identifier == uuid }) {
                print("[BLE] Found connected peripheral for UUID \(uuid), connecting...")
                logger.info("BLE", "Found connected peripheral, connecting with ANCS requirement...")
                pendingConnection = peripheral
                peripheral.delegate = self
                
                centralManager.connect(peripheral, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                    CBConnectPeripheralOptionRequiresANCS: true
                ])
            } else {
                print("[BLE] Could not find peripheral for UUID \(uuid), starting scan...")
                logger.warning("BLE", "Could not find peripheral for UUID \(uuid), starting scan...")
                // Start scanning to find the device
                lastError = .deviceNotFound(uuid)
                connectionState = .disconnected
            }
        }
    }
    
    /// Disconnect from the current device
    func disconnect() {
        guard let device = connectedDevice else { return }
        connectionState = .disconnecting
        centralManager.cancelPeripheralConnection(device.peripheral)
        print("[BLE] Disconnecting...")
    }
    
    /// Write data to a characteristic
    func write(data: Data, to characteristic: CBUUID, type: CBCharacteristicWriteType = .withResponse) async throws {
        guard let device = connectedDevice,
              let char = device.characteristics[characteristic] else {
            print("[BLE] Write failed: characteristic not found \(characteristic)")
            throw BluetoothError.characteristicNotFound
        }
        
        // Determine the best write type based on characteristic properties
        var actualType = type
        if type == .withResponse && !char.properties.contains(.write) {
            // Characteristic doesn't support write with response, try without
            if char.properties.contains(.writeWithoutResponse) {
                print("[BLE] Characteristic \(characteristic) doesn't support .withResponse, using .withoutResponse")
                actualType = .withoutResponse
            } else {
                print("[BLE] Characteristic \(characteristic) doesn't support any write type")
                throw BluetoothError.characteristicNotWritable
            }
        } else if type == .withoutResponse && !char.properties.contains(.writeWithoutResponse) {
            // Characteristic doesn't support write without response, try with
            if char.properties.contains(.write) {
                print("[BLE] Characteristic \(characteristic) doesn't support .withoutResponse, using .withResponse")
                actualType = .withResponse
            } else {
                print("[BLE] Characteristic \(characteristic) doesn't support any write type")
                throw BluetoothError.characteristicNotWritable
            }
        }
        
        // Check if there's already a pending write to this characteristic
        if writeCompletions[characteristic] != nil {
            print("[BLE] Warning: write already pending for \(characteristic), waiting...")
            // Wait a bit for the pending write to complete
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if writeCompletions[characteristic] != nil {
                print("[BLE] Cancelling stale write completion for \(characteristic)")
                writeCompletions.removeValue(forKey: characteristic)
            }
        }
        
        print("[BLE] Writing \(data.count) bytes to \(characteristic) (type: \(actualType == .withResponse ? "withResponse" : "withoutResponse"))")
        
        return try await withCheckedThrowingContinuation { continuation in
            if actualType == .withResponse {
                writeCompletions[characteristic] = { [weak self] error in
                    self?.writeCompletions.removeValue(forKey: characteristic)
                    if let error = error {
                        continuation.resume(throwing: BluetoothError.writeFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
                
                device.peripheral.writeValue(data, for: char, type: actualType)
            } else {
                // For withoutResponse, we complete immediately after writing
                device.peripheral.writeValue(data, for: char, type: actualType)
                continuation.resume()
            }
        }
    }
    
    /// Register a handler for characteristic notifications
    func registerNotificationHandler(for characteristic: CBUUID, handler: @escaping (Data) -> Void) {
        characteristicUpdateHandlers[characteristic] = handler
    }

    /// Remove a previously registered notification handler
    func unregisterNotificationHandler(for characteristic: CBUUID) {
        characteristicUpdateHandlers.removeValue(forKey: characteristic)
    }
    
    /// Enable notifications for a characteristic
    func enableNotifications(for characteristic: CBUUID) async throws {
        guard let device = connectedDevice,
              let char = device.characteristics[characteristic] else {
            throw BluetoothError.characteristicNotFound
        }
        
        device.peripheral.setNotifyValue(true, for: char)
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
            switch central.state {
            case .poweredOn:
                print("[BLE] Bluetooth powered on")
            case .poweredOff:
                print("[BLE] Bluetooth powered off")
                lastError = .bluetoothPoweredOff
                connectionState = .disconnected
            case .unauthorized:
                print("[BLE] Bluetooth unauthorized")
                lastError = .bluetoothUnauthorized
            case .unsupported:
                print("[BLE] Bluetooth unsupported")
                lastError = .bluetoothUnsupported
            default:
                break
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"
            
            if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                // Update existing device
                discoveredDevices[index].lastSeen = Date()
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
                print("[BLE] Discovered: \(name) (RSSI: \(RSSI))")
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            print("[BLE] Connected to \(peripheral.name ?? "Unknown")")
            logger.info("BLE", "Connected to \(peripheral.name ?? "Unknown")")
            connectionState = .discovering
            connectedDevice = ConnectedDevice(
                peripheral: peripheral,
                name: peripheral.name ?? "Fossil Watch"
            )
            
            // Check ANCS authorization status
            // This tells us if the user has enabled "Share System Notifications" for this peripheral
            let authorized = peripheral.ancsAuthorized
            ancsAuthorized = authorized
            print("[BLE] ANCS authorized: \(authorized)")
            logger.info("BLE", "ANCS authorized: \(authorized)")
            if !authorized {
                print("[BLE] To receive system notifications, enable 'Share System Notifications' in iOS Settings > Bluetooth > \(peripheral.name ?? "device") > (i)")
                logger.warning("BLE", "ANCS not authorized - enable 'Share System Notifications' in iOS Bluetooth settings")
            }
            
            // Discover ALL services first to see what the watch supports
            // This helps debug ANCS and understand watch capabilities
            peripheral.discoverServices(nil)
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            print("[BLE] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
            lastError = .connectionFailed(error)
            connectionState = .disconnected
            pendingConnection = nil
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            print("[BLE] Disconnected from \(peripheral.name ?? "Unknown")")
            connectedDevice = nil
            connectionState = .disconnected
            characteristicUpdateHandlers.removeAll()
            writeCompletions.removeAll()
            hasTransitionedToAuthenticating = false
            ancsAuthorized = false  // Reset ANCS status on disconnect
            
            if let error = error {
                lastError = .disconnected(error)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Handle state restoration for background operation
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            Task { @MainActor in
                for peripheral in peripherals {
                    print("[BLE] Restored peripheral: \(peripheral.name ?? "Unknown")")
                    peripheral.delegate = self
                }
            }
        }
    }
    
    /// Called when ANCS authorization status changes for a connected peripheral
    /// This happens when user toggles "Share System Notifications" in Bluetooth settings
    nonisolated func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        Task { @MainActor in
            let authorized = peripheral.ancsAuthorized
            ancsAuthorized = authorized
            print("[BLE] ANCS authorization updated: \(authorized)")
            
            if authorized {
                print("[BLE] ✅ ANCS authorized - watch will now receive system notifications!")
            } else {
                print("[BLE] ⚠️ ANCS not authorized - enable 'Share System Notifications' in iOS Bluetooth settings")
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] Service discovery error: \(error)")
                logger.error("BLE", "Service discovery error: \(error.localizedDescription)")
                lastError = .serviceDiscoveryFailed(error)
                return
            }
            
            guard let services = peripheral.services else { return }
            
            logger.info("BLE", "Discovered \(services.count) services")
            
            // ANCS Service UUID - if present, watch can subscribe to iOS notifications
            let ancsServiceUUID = CBUUID(string: "7905F431-B5CE-4E99-A40F-4B1E122D00D0")
            // Standard BLE service UUIDs for reference
            let knownServices: [CBUUID: String] = [
                CBUUID(string: "180A"): "Device Information Service",
                CBUUID(string: "180F"): "Battery Service",
                CBUUID(string: "1800"): "Generic Access",
                CBUUID(string: "1801"): "Generic Attribute",
                ancsServiceUUID: "Apple Notification Center Service (ANCS)",
                FossilConstants.serviceUUID: "Fossil Proprietary Service"
            ]
            
            var hasANCS = false
            var hasFossil = false
            
            for service in services {
                let serviceName = knownServices[service.uuid] ?? "Unknown"
                print("[BLE] Discovered service: \(service.uuid) (\(serviceName))")
                logger.debug("BLE", "Service: \(service.uuid) - \(serviceName)")
                
                if service.uuid == ancsServiceUUID {
                    hasANCS = true
                    // Discover ANCS characteristics to understand what watch supports
                    peripheral.discoverCharacteristics(nil, for: service)
                }
                
                if service.uuid == FossilConstants.serviceUUID {
                    hasFossil = true
                    peripheral.discoverCharacteristics(FossilConstants.allCharacteristics, for: service)
                }
            }
            
            // Log ANCS capability summary
            if hasANCS {
                logger.info("BLE", "✅ Watch EXPOSES ANCS service - it can receive notifications FROM iOS")
            } else {
                logger.info("BLE", "Watch does not expose ANCS service - this is normal, watch may SUBSCRIBE to iOS's ANCS instead")
            }
            
            if hasFossil {
                logger.info("BLE", "✅ Fossil proprietary service found")
            } else {
                logger.warning("BLE", "⚠️ Fossil service not found!")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] Characteristic discovery error: \(error)")
                lastError = .characteristicDiscoveryFailed(error)
                return
            }
            
            guard let characteristics = service.characteristics else { return }
            
            for characteristic in characteristics {
                // Log characteristic properties to help debug write type issues
                var props: [String] = []
                if characteristic.properties.contains(.read) { props.append("read") }
                if characteristic.properties.contains(.write) { props.append("write") }
                if characteristic.properties.contains(.writeWithoutResponse) { props.append("writeWithoutResponse") }
                if characteristic.properties.contains(.notify) { props.append("notify") }
                if characteristic.properties.contains(.indicate) { props.append("indicate") }
                print("[BLE] Discovered characteristic: \(characteristic.uuid) [\(props.joined(separator: ", "))]")
                
                connectedDevice?.characteristics[characteristic.uuid] = characteristic
                
                // Enable notifications/indications for characteristics that support it
                // Note: Some Fossil characteristics use .indicate instead of .notify
                // setNotifyValue works for both - the system handles the difference
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            
            // Check if we have all characteristics
            // Note: We wait until didUpdateNotificationStateFor confirms all notifications
            // are enabled before declaring the device ready
            if connectedDevice?.isReady == true {
                print("[BLE] All characteristics discovered, waiting for notification states...")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] Characteristic update error: \(error)")
                return
            }
            
            guard let data = characteristic.value else { return }
            
            print("[BLE] Received from \(characteristic.uuid): \(data.hexString)")
            
            // Call registered handler
            if let handler = characteristicUpdateHandlers[characteristic.uuid] {
                handler(data)
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] Write error for \(characteristic.uuid): \(error)")
            } else {
                print("[BLE] Write successful to \(characteristic.uuid)")
            }
            
            // Call the completion handler for this specific characteristic
            if let completion = writeCompletions[characteristic.uuid] {
                completion(error)
            } else {
                print("[BLE] Warning: No completion handler for write to \(characteristic.uuid)")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] Notification state error for \(characteristic.uuid): \(error)")
            } else {
                print("[BLE] Notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid)")
                
                // Track enabled notifications
                if characteristic.isNotifying {
                    connectedDevice?.notificationsEnabled.insert(characteristic.uuid)
                    
                    // Check if we're now fully ready (all characteristics + all notifications)
                    // Only trigger authentication transition ONCE
                    if !hasTransitionedToAuthenticating && connectedDevice?.isNotificationsReady == true {
                        hasTransitionedToAuthenticating = true
                        print("[BLE] All notifications enabled, device ready for authentication")
                        connectionState = .authenticating
                    }
                }
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
    case characteristicNotWritable
    case writeFailed(Error)
    case timeout
    case deviceNotFound(UUID)
    
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
        case .characteristicNotWritable:
            return "Characteristic does not support writing"
        case .writeFailed(let error):
            return "Write failed: \(error.localizedDescription)"
        case .timeout:
            return "Operation timed out"
        case .deviceNotFound(let uuid):
            return "Device not found: \(uuid)"
        }
    }
}
