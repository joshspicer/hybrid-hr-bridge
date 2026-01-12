import Foundation
import CoreBluetooth
import Combine

/// Manages reading device information from standard BLE Device Information Service
/// Source: QHybridSupport.java - reads from standard BLE characteristics
@MainActor
final class DeviceInfoManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var firmwareVersion: String?
    @Published private(set) var hardwareRevision: String?
    @Published private(set) var softwareRevision: String?
    @Published private(set) var serialNumber: String?
    @Published private(set) var manufacturerName: String?
    @Published private(set) var modelNumber: String?

    // MARK: - Types

    /// Standard BLE Device Information Service
    static let deviceInfoServiceUUID = CBUUID(string: "0000180A-0000-1000-8000-00805f9b34fb")

    /// Standard BLE characteristics
    enum Characteristic: String {
        case firmwareRevision = "00002a26-0000-1000-8000-00805f9b34fb"
        case hardwareRevision = "00002a27-0000-1000-8000-00805f9b34fb"
        case softwareRevision = "00002a28-0000-1000-8000-00805f9b34fb"
        case serialNumber = "00002a25-0000-1000-8000-00805f9b34fb"
        case manufacturerName = "00002a29-0000-1000-8000-00805f9b34fb"
        case modelNumber = "00002a24-0000-1000-8000-00805f9b34fb"

        var uuid: CBUUID {
            CBUUID(string: rawValue)
        }
    }

    // MARK: - Private Properties

    private let bluetoothManager: BluetoothManager
    private let logger = LogManager.shared
    private var discoveredCharacteristics: [CBUUID: CBCharacteristic] = [:]

    // MARK: - Initialization

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }

    // MARK: - Public API

    /// Read all device information
    func readDeviceInfo() async throws {
        logger.info("DeviceInfo", "Reading device information...")

        guard let device = bluetoothManager.connectedDevice else {
            throw DeviceInfoError.notConnected
        }

        // Discover Device Information Service if not already
        let peripheral = device.peripheral

        // Check if we already have the service discovered
        var deviceInfoService: CBService?
        if let services = peripheral.services {
            deviceInfoService = services.first { $0.uuid == Self.deviceInfoServiceUUID }
        }

        if deviceInfoService == nil {
            // Need to discover the service
            logger.info("DeviceInfo", "Discovering Device Information Service...")
            peripheral.discoverServices([Self.deviceInfoServiceUUID])

            // Wait for discovery
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            if let services = peripheral.services {
                deviceInfoService = services.first { $0.uuid == Self.deviceInfoServiceUUID }
            }
        }

        guard let service = deviceInfoService else {
            logger.warning("DeviceInfo", "Device Information Service not found")
            throw DeviceInfoError.serviceNotFound
        }

        // Discover characteristics
        if service.characteristics == nil || service.characteristics?.isEmpty == true {
            peripheral.discoverCharacteristics(nil, for: service)
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        }

        // Read each characteristic
        if let chars = service.characteristics {
            for char in chars {
                discoveredCharacteristics[char.uuid] = char

                // Read the value
                peripheral.readValue(for: char)
            }

            // Wait for reads to complete
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Parse the values
            parseCharacteristicValues()
        }

        logger.info("DeviceInfo", "Firmware: \(firmwareVersion ?? "unknown")")
        logger.info("DeviceInfo", "Hardware: \(hardwareRevision ?? "unknown")")
        logger.info("DeviceInfo", "Model: \(modelNumber ?? "unknown")")
    }

    // MARK: - Private Methods

    private func parseCharacteristicValues() {
        for (uuid, char) in discoveredCharacteristics {
            guard let value = char.value, !value.isEmpty else { continue }

            let stringValue = String(data: value, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)

            switch uuid.uuidString.lowercased() {
            case Characteristic.firmwareRevision.rawValue:
                firmwareVersion = stringValue
            case Characteristic.hardwareRevision.rawValue:
                hardwareRevision = stringValue
            case Characteristic.softwareRevision.rawValue:
                softwareRevision = stringValue
            case Characteristic.serialNumber.rawValue:
                serialNumber = stringValue
            case Characteristic.manufacturerName.rawValue:
                manufacturerName = stringValue
            case Characteristic.modelNumber.rawValue:
                modelNumber = stringValue
            default:
                break
            }
        }
    }

    /// Parse firmware version to extract clean version number
    /// Fossil firmware format: "DN1.0.2.20r.v4.27" -> extracts "4.27"
    func parsedFirmwareVersion() -> String? {
        guard let fw = firmwareVersion else { return nil }

        // Pattern: look for version after ".v" like "4.27" from "DN1.0.2.20r.v4.27"
        let pattern = #"(?<=\.v)\d+\.\d+"#
        if let range = fw.range(of: pattern, options: .regularExpression) {
            return String(fw[range])
        }

        return firmwareVersion
    }

    /// Determine if this is an HR model based on firmware
    /// Source: WatchAdapterFactory.java
    func isHRModel() -> Bool {
        guard let fw = firmwareVersion else { return false }

        // HR models have hardware version '1' at position 2
        // Or start with "IV0", "VA", "WA"
        if fw.count >= 3 {
            let char2 = fw[fw.index(fw.startIndex, offsetBy: 2)]
            if char2 == "1" { return true }
        }

        if fw.hasPrefix("IV0") || fw.hasPrefix("VA") || fw.hasPrefix("WA") {
            return true
        }

        return false
    }
}

// MARK: - Errors

enum DeviceInfoError: Error, LocalizedError {
    case notConnected
    case serviceNotFound
    case readFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to device"
        case .serviceNotFound:
            return "Device Information Service not found"
        case .readFailed:
            return "Failed to read device information"
        }
    }
}
