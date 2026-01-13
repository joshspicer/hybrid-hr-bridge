import Foundation
import Combine

/// Manages alarms on the watch
/// Implements the alarm protocol from Gadgetbridge
/// Source: Alarm.java, AlarmsSetRequest.java
@MainActor
final class AlarmManager: ObservableObject {

    // MARK: - Types

    /// Represents an alarm that can be set on the watch
    struct WatchAlarm: Identifiable, Codable, Equatable {
        let id: UUID
        var hour: Int
        var minute: Int
        var enabled: Bool
        var repeatDays: RepeatDays
        var title: String
        var message: String

        init(id: UUID = UUID(),
             hour: Int,
             minute: Int,
             enabled: Bool = true,
             repeatDays: RepeatDays = .none,
             title: String = "Alarm",
             message: String = "") {
            self.id = id
            self.hour = hour
            self.minute = minute
            self.enabled = enabled
            self.repeatDays = repeatDays
            self.title = title
            self.message = message
        }

        /// Convert to 3-byte format for old alarm format
        /// Source: Alarm.java#L59-L71
        func toBytes() -> Data {
            // Byte 0: 0xFF if single-shot, or (0x80 | days) if repeating
            // Byte 1: minute, with bit 7 set if repeating
            // Byte 2: hour
            let isRepeating = repeatDays != .none
            let daysByte: UInt8 = isRepeating ? (0x80 | repeatDays.rawValue) : 0xFF
            let minuteByte: UInt8 = isRepeating ? (UInt8(minute) | 0x80) : UInt8(minute)
            let hourByte = UInt8(hour)

            return Data([daysByte, minuteByte, hourByte])
        }
    }

    /// Days of the week for repeating alarms
    /// Uses bit flags matching Gadgetbridge format
    struct RepeatDays: OptionSet, Codable, Equatable {
        let rawValue: UInt8

        static let sunday    = RepeatDays(rawValue: 1 << 0)
        static let monday    = RepeatDays(rawValue: 1 << 1)
        static let tuesday   = RepeatDays(rawValue: 1 << 2)
        static let wednesday = RepeatDays(rawValue: 1 << 3)  // Note: Gadgetbridge has Wed/Thu swapped
        static let thursday  = RepeatDays(rawValue: 1 << 4)
        static let friday    = RepeatDays(rawValue: 1 << 5)
        static let saturday  = RepeatDays(rawValue: 1 << 6)

        static let none: RepeatDays = []
        static let weekdays: RepeatDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        static let weekends: RepeatDays = [.saturday, .sunday]
        static let everyday: RepeatDays = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    }

    // MARK: - Published State

    @Published var alarms: [WatchAlarm] = []

    // MARK: - Private Properties

    private let fileTransferManager: FileTransferManager
    private let logger = LogManager.shared
    private let userDefaults = UserDefaults.standard
    private let alarmsKey = "watchAlarms"

    /// File format version - newer watches use v3 with labels
    private let fileVersion: UInt16 = 0x03

    // MARK: - Initialization

    init(fileTransferManager: FileTransferManager) {
        self.fileTransferManager = fileTransferManager
        loadAlarms()
    }

    // MARK: - Public API

    /// Add a new alarm
    func addAlarm(_ alarm: WatchAlarm) {
        alarms.append(alarm)
        saveAlarms()
    }

    /// Update an existing alarm
    func updateAlarm(_ alarm: WatchAlarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
            saveAlarms()
        }
    }

    /// Remove an alarm
    func removeAlarm(_ alarm: WatchAlarm) {
        alarms.removeAll { $0.id == alarm.id }
        saveAlarms()
    }

    /// Remove alarm by ID
    func removeAlarm(id: UUID) {
        alarms.removeAll { $0.id == id }
        saveAlarms()
    }

    /// Sync all alarms to the watch
    func syncAlarms() async throws {
        let enabledAlarms = alarms.filter { $0.enabled }
        logger.info("Alarms", "Syncing \(enabledAlarms.count) alarms to watch")

        let data = buildAlarmsPayload(enabledAlarms)

        logger.debug("Alarms", "Payload size: \(data.count) bytes")

        try await fileTransferManager.putFile(data, to: .alarms)

        logger.info("Alarms", "Alarms synced successfully")
    }

    /// Create and sync a quick alarm (e.g., for timers)
    func setQuickAlarm(hour: Int, minute: Int, title: String = "Timer") async throws {
        let alarm = WatchAlarm(
            hour: hour,
            minute: minute,
            enabled: true,
            title: title
        )
        addAlarm(alarm)
        try await syncAlarms()
    }

    // MARK: - Private Methods

    /// Build the alarm file payload
    /// Source: AlarmsSetRequest.java#L35-L87
    private func buildAlarmsPayload(_ alarms: [WatchAlarm]) -> Data {
        // Use new format (v3) with labels
        // Each alarm entry:
        // - 1 byte: 0x00 (unknown)
        // - 2 bytes: entry size (little-endian)
        // - Entry 0x00 (time data): 1 byte id, 2 bytes length, 3 bytes data
        // - Entry 0x01 (label): 1 byte id, 2 bytes length, null-terminated string
        // - Entry 0x02 (message): 1 byte id, 2 bytes length, null-terminated string

        var totalSize = 0
        var processedAlarms: [(alarm: WatchAlarm, label: Data, message: Data)] = []

        for alarm in alarms {
            // Truncate and prepare strings
            var label = alarm.title
            if label.isEmpty { label = "---" }
            label = String(label.prefix(15))

            var message = alarm.message
            if message.isEmpty { message = "---" }
            message = String(message.prefix(50))

            let labelData = (label + "\0").data(using: .utf8) ?? Data([0])
            let messageData = (message + "\0").data(using: .utf8) ?? Data([0])

            // Calculate entry size: 17 bytes fixed + label + message
            let entrySize = 17 + labelData.count + messageData.count
            totalSize += entrySize

            processedAlarms.append((alarm, labelData, messageData))
        }

        var buffer = ByteBuffer(capacity: totalSize)

        for (alarm, labelData, messageData) in processedAlarms {
            let entrySize = 17 + labelData.count + messageData.count

            // Entry header
            buffer.putUInt8(0x00)  // Unknown byte
            buffer.putUInt16(UInt16(entrySize - 3))  // Size excluding first 3 bytes

            // Time data entry (id: 0x00)
            buffer.putUInt8(0x00)  // Entry ID
            buffer.putUInt16(3)    // Entry length
            buffer.putData(alarm.toBytes())  // 3-byte alarm data

            // Label entry (id: 0x01)
            buffer.putUInt8(0x01)  // Entry ID
            buffer.putUInt16(UInt16(labelData.count))  // Entry length
            buffer.putData(labelData)

            // Message entry (id: 0x02)
            buffer.putUInt8(0x02)  // Entry ID
            buffer.putUInt16(UInt16(messageData.count))  // Entry length
            buffer.putData(messageData)
        }

        return buffer.data
    }

    private func loadAlarms() {
        if let data = userDefaults.data(forKey: alarmsKey),
           let decoded = try? JSONDecoder().decode([WatchAlarm].self, from: data) {
            alarms = decoded
        }
    }

    private func saveAlarms() {
        if let data = try? JSONEncoder().encode(alarms) {
            userDefaults.set(data, forKey: alarmsKey)
        }
    }
}
