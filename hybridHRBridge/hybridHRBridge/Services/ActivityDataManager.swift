import Foundation
import Combine

/// Manages fetching and parsing activity data from the watch
/// Uses FileTransferManager for the actual encrypted file fetch
///
/// Source: FossilHRWatchAdapter.java#L1279-L1339
/// https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil_hr/FossilHRWatchAdapter.java
@MainActor
final class ActivityDataManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isFetching = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastFetchedData: ActivityData?
    @Published private(set) var lastError: ActivityFetchError?
    
    // MARK: - Private Properties
    
    private let fileTransferManager: FileTransferManager
    private let authManager: AuthenticationManager
    private let logger = LogManager.shared
    private let parser = ActivityFileParser()
    
    // MARK: - Initialization
    
    init(bluetoothManager: BluetoothManager, authManager: AuthenticationManager) {
        self.fileTransferManager = FileTransferManager(bluetoothManager: bluetoothManager, authManager: authManager)
        self.authManager = authManager
    }
    
    /// Initialize with an existing FileTransferManager (preferred)
    init(fileTransferManager: FileTransferManager, authManager: AuthenticationManager) {
        self.fileTransferManager = fileTransferManager
        self.authManager = authManager
    }
    
    // MARK: - Public API
    
    /// Fetch activity data from the watch
    /// Uses FileTransferManager to perform the encrypted file read
    ///
    /// - Returns: Parsed activity data containing steps, heart rate, calories, etc.
    func fetchActivityData() async throws -> ActivityData {
        guard !isFetching else {
            throw ActivityFetchError.fetchInProgress
        }
        
        guard authManager.isAuthenticated else {
            logger.error("Activity", "Cannot fetch activity data - not authenticated")
            throw ActivityFetchError.notAuthenticated
        }
        
        isFetching = true
        progress = 0
        lastError = nil
        
        defer {
            isFetching = false
            progress = 0
        }
        
        logger.info("Activity", "Starting activity data fetch")
        
        do {
            // Fetch the encrypted activity file using FileTransferManager
            logger.info("Activity", "Fetching encrypted activity file")
            progress = 0.1
            
            let fileData = try await fileTransferManager.fetchEncryptedFile(for: .activityFile)
            logger.info("Activity", "Received \(fileData.count) bytes of activity data")
            progress = 0.8
            
            // Parse the activity data
            logger.info("Activity", "Parsing activity data")
            let activityData = try parser.parseFile(fileData)
            progress = 1.0
            
            lastFetchedData = activityData
            logger.info("Activity", "✅ Activity fetch complete - \(activityData.samples.count) samples, \(activityData.totalSteps) total steps")
            
            return activityData
            
        } catch let error as FileTransferError {
            logger.error("Activity", "Activity fetch failed: \(error.localizedDescription)")
            let fetchError = ActivityFetchError.fetchFailed(error)
            lastError = fetchError
            throw fetchError
        } catch {
            logger.error("Activity", "Activity fetch failed: \(error.localizedDescription)")
            let fetchError = error as? ActivityFetchError ?? .fetchFailed(error)
            lastError = fetchError
            throw fetchError
        }
    }
}

// MARK: - Errors

enum ActivityFetchError: Error, LocalizedError {
    case fetchInProgress
    case notAuthenticated
    case fetchFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .fetchInProgress:
            return "Activity fetch already in progress"
        case .notAuthenticated:
            return "Not authenticated with watch"
        case .fetchFailed(let error):
            return "Fetch failed: \(error.localizedDescription)"
        }
    }
}
