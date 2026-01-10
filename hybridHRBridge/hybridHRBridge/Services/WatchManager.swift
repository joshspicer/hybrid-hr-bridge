import Foundation
import Combine
import CoreBluetooth

/// Central manager coordinating all watch functionality
@MainActor
final class WatchManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var connectionStatus: WatchConnectionStatus = .disconnected
    @Published private(set) var connectedWatch: WatchDevice?
    @Published var savedDevices: [WatchDevice] = []
    @Published private(set) var lastError: Error?
    
    // MARK: - Managers
    
    let bluetoothManager: BluetoothManager
    let authManager: AuthenticationManager
    let fileTransferManager: FileTransferManager
    let activityDataManager: ActivityDataManager
    
    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    private let devicesKey = "savedDevices"
    private let lastConnectedDeviceKey = "lastConnectedDeviceId"
    private var hasAttemptedAutoReconnect = false
    private var pendingAuthentication = false
    private let logger = LogManager.shared

    // MARK: - Initialization

    init() {
        bluetoothManager = BluetoothManager()
        authManager = AuthenticationManager(bluetoothManager: bluetoothManager)
        fileTransferManager = FileTransferManager(bluetoothManager: bluetoothManager, authManager: authManager)
        // Share the FileTransferManager with ActivityDataManager to prevent handler conflicts
        activityDataManager = ActivityDataManager(fileTransferManager: fileTransferManager, authManager: authManager)

        loadSavedDevices()
        setupBindings()

        // Attempt to reconnect to last device when Bluetooth becomes available
        setupAutoReconnect()
    }
    
    // MARK: - Device Discovery
    
    /// Start scanning for watches
    func startScanning() {
        connectionStatus = .scanning
        bluetoothManager.startScanning()
    }
    
    /// Stop scanning
    func stopScanning() {
        bluetoothManager.stopScanning()
        if connectionStatus == .scanning {
            connectionStatus = .disconnected
        }
    }
    
    /// Get discovered devices
    var discoveredDevices: [BluetoothManager.DiscoveredDevice] {
        bluetoothManager.discoveredDevices
    }
    
    // MARK: - Connection
    
    /// Connect to a discovered device
    func connect(to device: BluetoothManager.DiscoveredDevice) {
        connectionStatus = .connecting
        bluetoothManager.connect(to: device)
    }
    
    /// Connect to a saved device by ID
    func connect(toSavedDevice id: UUID) {
        guard savedDevices.contains(where: { $0.id == id }) else {
            lastError = WatchManagerError.deviceNotFound
            return
        }

        connectionStatus = .connecting
        bluetoothManager.connect(toDeviceWithUUID: id)
    }
    
    /// Disconnect from the current device
    func disconnect() {
        bluetoothManager.disconnect()
        authManager.resetAuthState()
        connectionStatus = .disconnected
        connectedWatch = nil
    }
    
    // MARK: - Authentication
    
    /// Authenticate with the connected watch using stored key
    func authenticate() async throws {
        guard let watch = connectedWatch, let key = watch.secretKey else {
            throw WatchManagerError.noSecretKey
        }
        
        connectionStatus = .authenticating
        try authManager.setSecretKey(key)
        try await authManager.authenticate()
        connectionStatus = .connected
    }
    
    /// Set secret key for a device
    func setSecretKey(_ key: String, for deviceId: UUID) throws {
        logger.info("WatchManager", "Setting secret key for device: \(deviceId)")
        logger.debug("WatchManager", "Raw key length: \(key.count)")
        
        // Validate key format - only strip 0x prefix, not from middle of string
        var cleanKey = key.replacingOccurrences(of: " ", with: "")
        if cleanKey.lowercased().hasPrefix("0x") {
            cleanKey = String(cleanKey.dropFirst(2))
        }
        
        logger.debug("WatchManager", "Cleaned key length: \(cleanKey.count)")
        
        guard cleanKey.count == 32 else {
            logger.error("WatchManager", "Invalid key format - expected 32 hex chars, got \(cleanKey.count)")
            throw WatchManagerError.invalidKeyFormat
        }
        
        guard cleanKey.allSatisfy({ $0.isHexDigit }) else {
            logger.error("WatchManager", "Invalid key format - contains non-hex characters")
            throw WatchManagerError.invalidKeyFormat
        }
        
        // Update saved device
        if let index = savedDevices.firstIndex(where: { $0.id == deviceId }) {
            savedDevices[index].secretKey = cleanKey
            saveSavedDevices()
            logger.info("WatchManager", "Updated saved device with new key")
        } else {
            logger.warning("WatchManager", "Device \(deviceId) not found in saved devices")
        }
        
        // Update current device if connected
        if connectedWatch?.id == deviceId {
            connectedWatch?.secretKey = cleanKey
            logger.info("WatchManager", "Updated connected watch with new key")
        }
        
        logger.info("WatchManager", "Secret key set successfully")
    }
    
    // MARK: - Notifications
    
    /// Send a notification to the watch
    /// Note: Notifications do NOT require authentication per Gadgetbridge - only BLE connection
    /// Source: FossilHRWatchAdapter.java - playRawNotification uses FilePutRequest (not FileEncryptedInterface)
    func sendNotification(
        type: NotificationType,
        title: String,
        sender: String,
        message: String,
        appIdentifier: String
    ) async throws {
        guard connectionStatus != .disconnected else {
            throw WatchManagerError.notConnected
        }
        
        try await fileTransferManager.sendNotification(
            type: type,
            title: title,
            sender: sender,
            message: message,
            appIdentifier: appIdentifier
        )
    }
    
    /// Dismiss a notification on the watch
    /// Note: Like sending notifications, dismissing does NOT require authentication
    /// Source: FossilHRWatchAdapter.java#L1448 - uses DismissTextNotificationRequest (not encrypted)
    func dismissNotification(messageId: UInt32) async throws {
        guard connectionStatus != .disconnected else {
            throw WatchManagerError.notConnected
        }
        
        let payload = RequestBuilder.buildNotification(
            type: .dismissNotification,
            title: "",
            sender: "",
            message: "",
            packageCRC: 0,
            messageID: messageId
        )
        
        try await fileTransferManager.putFile(payload, to: .notificationPlay, requiresAuth: false)
    }
    
    // MARK: - Time Sync
    
    /// Sync time to the watch
    func syncTime() async throws {
        guard authManager.isAuthenticated else {
            throw WatchManagerError.notAuthenticated
        }
        
        try await fileTransferManager.syncTime()
    }
    
    // MARK: - Activity Data
    
    /// Fetch activity data (steps, heart rate, calories, etc.) from the watch
    func fetchActivityData() async throws -> ActivityData {
        guard authManager.isAuthenticated else {
            throw WatchManagerError.notAuthenticated
        }
        
        return try await activityDataManager.fetchActivityData()
    }
    
    // MARK: - Watch Apps
    
    /// Install a watch app from .wapp file data
    func installApp(_ wappData: Data) async throws {
        guard authManager.isAuthenticated else {
            throw WatchManagerError.notAuthenticated
        }
        
        try await fileTransferManager.installApp(wappData: wappData)
    }
    
    /// Install a watch app from file URL
    func installApp(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        try await installApp(data)
    }

    /// Refresh battery status by reading encrypted configuration file
    func refreshBatteryStatus() async throws -> BatteryStatus {
        guard authManager.isAuthenticated else {
            throw WatchManagerError.notAuthenticated
        }

        guard connectionStatus != .disconnected else {
            throw WatchManagerError.notConnected
        }

        let status = try await fileTransferManager.readBatteryStatus()
        logger.info("Battery", "Battery level \(status.percentage)% (\(status.voltageMillivolts) mV)")

        if var watch = connectedWatch {
            watch.batteryLevel = status.percentage
            watch.batteryVoltageMillivolts = status.voltageMillivolts
            connectedWatch = watch

            if let index = savedDevices.firstIndex(where: { $0.id == watch.id }) {
                savedDevices[index].batteryLevel = status.percentage
                savedDevices[index].batteryVoltageMillivolts = status.voltageMillivolts
                saveSavedDevices()
            }
        }

        return status
    }
    
    // MARK: - Device Management
    
    /// Save a device for future connections
    func saveDevice(_ device: BluetoothManager.DiscoveredDevice) {
        let watchDevice = WatchDevice(id: device.id, name: device.name)
        
        if !savedDevices.contains(where: { $0.id == device.id }) {
            savedDevices.append(watchDevice)
            saveSavedDevices()
        }
    }
    
    /// Remove a saved device
    func removeSavedDevice(_ id: UUID) {
        savedDevices.removeAll { $0.id == id }
        saveSavedDevices()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Observe Bluetooth connection state
        bluetoothManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state)
            }
            .store(in: &cancellables)
        
        // Observe connected device
        bluetoothManager.$connectedDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                self?.handleDeviceChange(device)
            }
            .store(in: &cancellables)
        
        // Observe errors
        bluetoothManager.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.lastError = error
            }
            .store(in: &cancellables)
        
        authManager.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.lastError = error
            }
            .store(in: &cancellables)
    }
    
    private func handleConnectionStateChange(_ state: BluetoothManager.ConnectionState) {
        switch state {
        case .disconnected:
            connectionStatus = .disconnected
            // Reset auth state on disconnect so we re-auth on next connection
            authManager.resetAuthState()
            pendingAuthentication = false
        case .scanning:
            connectionStatus = .scanning
        case .connecting:
            connectionStatus = .connecting
        case .discovering, .authenticating:
            connectionStatus = .authenticating
        case .connected:
            // Set flag to authenticate once device info is available
            // The actual auth happens in handleDeviceChange after connectedWatch is set
            pendingAuthentication = true
            connectionStatus = .authenticating
            logger.info("WatchManager", "Device connected, waiting for device info before auth...")
        case .disconnecting:
            connectionStatus = .disconnected
            authManager.resetAuthState()
            pendingAuthentication = false
        }
    }
    
    private func handleDeviceChange(_ device: BluetoothManager.ConnectedDevice?) {
        if let device = device {
            // Check if we have a saved device with this ID
            if let saved = savedDevices.first(where: { $0.id == device.peripheral.identifier }) {
                connectedWatch = saved
                connectedWatch?.lastConnected = Date()
                logger.info("WatchManager", "Loaded saved device '\(saved.name)' with secretKey: \(saved.secretKey != nil ? "yes" : "no")")
                // Update the saved device with last connected time
                if let index = savedDevices.firstIndex(where: { $0.id == device.peripheral.identifier }) {
                    savedDevices[index].lastConnected = Date()
                    saveSavedDevices()
                }
            } else {
                // Create new device
                connectedWatch = WatchDevice(id: device.peripheral.identifier, name: device.name)
                logger.info("WatchManager", "Created new device '\(device.name)' (no saved key)")
            }

            // Save as last connected device
            userDefaults.set(device.peripheral.identifier.uuidString, forKey: lastConnectedDeviceKey)
            logger.debug("WatchManager", "Saved last connected device: \(device.peripheral.identifier)")
            
            // Now trigger authentication if we were waiting for device info
            if pendingAuthentication {
                pendingAuthentication = false
                Task {
                    await performAutoAuthentication()
                }
            }
        } else {
            connectedWatch = nil
        }
    }
    
    private func performAutoAuthentication() async {
        guard let watch = connectedWatch else {
            logger.warning("WatchManager", "No connected watch for auto-auth")
            connectionStatus = .connected
            return
        }
        
        guard watch.secretKey != nil else {
            logger.info("WatchManager", "No secret key available for '\(watch.name)' - manual auth required")
            connectionStatus = .connected
            return
        }
        
        logger.info("WatchManager", "Starting automatic authentication for '\(watch.name)'...")
        
        do {
            try await authenticate()
            logger.info("WatchManager", "✅ Auto-authentication successful!")
        } catch {
            logger.error("WatchManager", "Auto-auth failed: \(error.localizedDescription)")
            // Stay connected even if auth fails - user can retry manually
            connectionStatus = .connected
        }
    }

    private func setupAutoReconnect() {
        // Monitor Bluetooth state to auto-reconnect when it becomes available
        bluetoothManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }

                // Only attempt auto-reconnect once when Bluetooth becomes ready
                // and we're in disconnected state
                if self.hasAttemptedAutoReconnect {
                    return
                }

                if state != .disconnected {
                    return
                }

                // Check if we should auto-reconnect
                if let lastDeviceUUIDString = self.userDefaults.string(forKey: self.lastConnectedDeviceKey),
                   let lastDeviceUUID = UUID(uuidString: lastDeviceUUIDString),
                   let savedDevice = self.savedDevices.first(where: { $0.id == lastDeviceUUID }),
                   savedDevice.secretKey != nil {

                    print("[WatchManager] Found last connected device '\(savedDevice.name)' with key - attempting auto-reconnect")
                    self.hasAttemptedAutoReconnect = true

                    // Small delay to ensure Bluetooth is fully ready
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        await MainActor.run {
                            if self.connectionStatus == .disconnected {
                                print("[WatchManager] Auto-reconnecting to saved device")
                                self.connect(toSavedDevice: lastDeviceUUID)
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadSavedDevices() {
        if let data = userDefaults.data(forKey: devicesKey),
           let devices = try? JSONDecoder().decode([WatchDevice].self, from: data) {
            savedDevices = devices
        }
    }
    
    private func saveSavedDevices() {
        if let data = try? JSONEncoder().encode(savedDevices) {
            userDefaults.set(data, forKey: devicesKey)
            userDefaults.synchronize()  // Force immediate save
            print("[WatchManager] Saved \(savedDevices.count) devices to UserDefaults")
        } else {
            print("[WatchManager] Failed to encode devices for saving")
        }
    }
}

// MARK: - Errors

enum WatchManagerError: Error, LocalizedError {
    case deviceNotFound
    case noSecretKey
    case invalidKeyFormat
    case notAuthenticated
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Device not found"
        case .noSecretKey:
            return "No secret key configured for this device"
        case .invalidKeyFormat:
            return "Invalid key format. Must be 32 hex characters."
        case .notAuthenticated:
            return "Not authenticated with watch"
        case .notConnected:
            return "Not connected to a watch"
        }
    }
}
