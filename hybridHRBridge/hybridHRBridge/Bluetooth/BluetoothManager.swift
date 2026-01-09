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
        
        centralManager.connect(device.peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        
        print("[BLE] Connecting to \(device.name)...")
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
            throw BluetoothError.characteristicNotFound
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            if type == .withResponse {
                writeCompletionHandler = { error in
                    if let error = error {
                        continuation.resume(throwing: BluetoothError.writeFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
            }
            
            device.peripheral.writeValue(data, for: char, type: type)
            
            if type == .withoutResponse {
                continuation.resume()
            }
        }
    }
    
    /// Register a handler for characteristic notifications
    func registerNotificationHandler(for characteristic: CBUUID, handler: @escaping (Data) -> Void) {
        characteristicUpdateHandlers[characteristic] = handler
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
            connectionState = .discovering
            connectedDevice = ConnectedDevice(
                peripheral: peripheral,
                name: peripheral.name ?? "Fossil Watch"
            )
            
            // Discover services
            peripheral.discoverServices([FossilConstants.serviceUUID])
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
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] Service discovery error: \(error)")
                lastError = .serviceDiscoveryFailed(error)
                return
            }
            
            guard let services = peripheral.services else { return }
            
            for service in services {
                print("[BLE] Discovered service: \(service.uuid)")
                if service.uuid == FossilConstants.serviceUUID {
                    peripheral.discoverCharacteristics(FossilConstants.allCharacteristics, for: service)
                }
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
                print("[BLE] Discovered characteristic: \(characteristic.uuid)")
                connectedDevice?.characteristics[characteristic.uuid] = characteristic
                
                // Enable notifications for characteristics that support it
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            
            // Check if we have all characteristics
            if connectedDevice?.isReady == true {
                print("[BLE] All characteristics discovered, device ready")
                connectionState = .authenticating
                // Authentication will be handled by AuthenticationManager
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
                print("[BLE] Write error: \(error)")
            } else {
                print("[BLE] Write successful to \(characteristic.uuid)")
            }
            
            writeCompletionHandler?(error)
            writeCompletionHandler = nil
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] Notification state error for \(characteristic.uuid): \(error)")
            } else {
                print("[BLE] Notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid)")
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
        }
    }
}
