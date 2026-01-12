import Foundation
import CoreBluetooth
import Combine

/// Manages real-time heart rate monitoring from the watch
/// Source: FossilHRWatchAdapter.java#L1969-L1975
@MainActor
final class HeartRateManager: ObservableObject {

    // MARK: - Published State

    /// Current heart rate in BPM (0 if not measuring)
    @Published private(set) var currentHeartRate: Int = 0

    /// Whether heart rate monitoring is active
    @Published private(set) var isMonitoring: Bool = false

    /// Last update timestamp
    @Published private(set) var lastUpdate: Date?

    // MARK: - Private Properties

    private let bluetoothManager: BluetoothManager
    private let logger = LogManager.shared
    private var notificationHandler: ((Data) -> Void)?

    // Standard BLE Heart Rate Service UUID
    static let heartRateServiceUUID = CBUUID(string: "0000180D-0000-1000-8000-00805f9b34fb")

    // MARK: - Initialization

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }

    // MARK: - Public API

    /// Start monitoring heart rate
    /// Subscribes to the standard BLE heart rate characteristic
    func startMonitoring() async throws {
        guard !isMonitoring else {
            logger.info("HeartRate", "Already monitoring")
            return
        }

        logger.info("HeartRate", "Starting heart rate monitoring...")

        // Set up notification handler for heart rate data
        // The heart rate characteristic uses standard BLE format:
        // Byte 0: Flags (bit 0 = format: 0=UINT8, 1=UINT16)
        // Byte 1 (or 1-2): Heart rate value
        notificationHandler = { [weak self] data in
            Task { @MainActor in
                self?.handleHeartRateData(data)
            }
        }

        // Subscribe to heart rate notifications
        try await bluetoothManager.subscribeToCharacteristic(
            FossilConstants.characteristicHeartRate,
            handler: notificationHandler!
        )

        isMonitoring = true
        logger.info("HeartRate", "Heart rate monitoring started")
    }

    /// Stop monitoring heart rate
    func stopMonitoring() async throws {
        guard isMonitoring else {
            return
        }

        logger.info("HeartRate", "Stopping heart rate monitoring...")

        try await bluetoothManager.unsubscribeFromCharacteristic(
            FossilConstants.characteristicHeartRate
        )

        isMonitoring = false
        currentHeartRate = 0
        notificationHandler = nil
        logger.info("HeartRate", "Heart rate monitoring stopped")
    }

    // MARK: - Private Methods

    private func handleHeartRateData(_ data: Data) {
        guard data.count >= 2 else {
            logger.warning("HeartRate", "Invalid heart rate data length: \(data.count)")
            return
        }

        // Parse standard BLE heart rate format
        // Source: FossilHRWatchAdapter.java#L1972 - int heartRate = value[1]
        let flags = data[0]
        let isUInt16Format = (flags & 0x01) != 0

        let heartRate: Int
        if isUInt16Format && data.count >= 3 {
            // 16-bit heart rate value (little endian)
            heartRate = Int(data[1]) | (Int(data[2]) << 8)
        } else {
            // 8-bit heart rate value
            heartRate = Int(data[1])
        }

        // Validate heart rate is in reasonable range
        guard heartRate > 0 && heartRate < 250 else {
            logger.debug("HeartRate", "Heart rate out of range: \(heartRate)")
            return
        }

        currentHeartRate = heartRate
        lastUpdate = Date()

        logger.debug("HeartRate", "Heart rate: \(heartRate) BPM")
    }
}
