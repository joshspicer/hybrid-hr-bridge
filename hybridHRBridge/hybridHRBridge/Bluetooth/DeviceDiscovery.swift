import Foundation
import CoreBluetooth

/// Handles Bluetooth device discovery and scanning operations
@MainActor
final class DeviceDiscovery: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    
    // MARK: - Types
    
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
    
    // MARK: - Private Properties
    
    private let logger = LogManager.shared
    private weak var centralManager: CBCentralManager?
    
    // MARK: - Initialization
    
    init() {}
    
    func setCentralManager(_ manager: CBCentralManager) {
        self.centralManager = manager
    }
    
    // MARK: - Public API
    
    /// Start scanning for Fossil Hybrid HR watches
    func startScanning() {
        guard let centralManager = centralManager else {
            logger.error("Discovery", "Central manager not set")
            return
        }
        
        guard centralManager.state == .poweredOn else {
            logger.error("Discovery", "Bluetooth not powered on")
            return
        }
        
        discoveredDevices.removeAll()
        isScanning = true
        
        centralManager.scanForPeripherals(
            withServices: [FossilConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        logger.info("Discovery", "Started scanning for Fossil devices")
    }
    
    /// Stop scanning for devices
    func stopScanning() {
        guard let centralManager = centralManager else { return }
        
        centralManager.stopScan()
        isScanning = false
        logger.info("Discovery", "Stopped scanning")
    }
    
    /// Handle discovered peripheral
    func handleDiscoveredPeripheral(_ peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = peripheral.name ?? "Unknown Device"
        let rssiValue = rssi.intValue
        
        // Update or add device
        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[index].lastSeen = Date()
        } else {
            let device = DiscoveredDevice(
                id: peripheral.identifier,
                peripheral: peripheral,
                name: name,
                rssi: rssiValue,
                lastSeen: Date()
            )
            discoveredDevices.append(device)
            logger.info("Discovery", "Discovered device: \(name) (RSSI: \(rssiValue))")
        }
    }
    
    /// Retrieve a peripheral by UUID
    func retrievePeripheral(withIdentifier uuid: UUID) -> CBPeripheral? {
        guard let centralManager = centralManager else { return nil }
        
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        return peripherals.first
    }
    
    /// Retrieve connected peripherals with Fossil service
    func retrieveConnectedPeripherals() -> [CBPeripheral] {
        guard let centralManager = centralManager else { return [] }
        
        return centralManager.retrieveConnectedPeripherals(withServices: [FossilConstants.serviceUUID])
    }
}
