import Foundation
import os.log

/// Centralized logging manager with file export capability
/// Captures all app logs for debugging connection and authentication issues
@MainActor
final class LogManager: ObservableObject {

    // MARK: - Singleton

    static let shared = LogManager()

    // MARK: - Properties

    @Published private(set) var logEntries: [LogEntry] = []
    private let maxLogEntries = 5000  // Keep last 5000 entries in memory

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private let fileManager = FileManager.default

    // MARK: - Types

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let category: String
        let message: String

        var formattedMessage: String {
            let dateStr = ISO8601DateFormatter().string(from: timestamp)
            return "[\(dateStr)] [\(level.rawValue)] [\(category)] \(message)"
        }
    }

    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    // MARK: - Initialization

    private init() {
        log(.info, category: "LogManager", message: "LogManager initialized")
    }

    // MARK: - Logging Methods

    func log(_ level: LogLevel, category: String, message: String) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )

        logEntries.append(entry)

        // Trim if exceeds max
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }

        // Also print to console
        print("[\(category)] \(message)")

        // Log to system logger for crash reports
        let osLog = OSLog(subsystem: "com.hybridhrbridge", category: category)
        switch level {
        case .debug:
            os_log(.debug, log: osLog, "%{public}@", message)
        case .info:
            os_log(.info, log: osLog, "%{public}@", message)
        case .warning:
            os_log(.default, log: osLog, "%{public}@", message)
        case .error:
            os_log(.error, log: osLog, "%{public}@", message)
        }
    }

    // Convenience methods
    func debug(_ category: String, _ message: String) {
        log(.debug, category: category, message: message)
    }

    func info(_ category: String, _ message: String) {
        log(.info, category: category, message: message)
    }

    func warning(_ category: String, _ message: String) {
        log(.warning, category: category, message: message)
    }

    func error(_ category: String, _ message: String) {
        log(.error, category: category, message: message)
    }

    // MARK: - Export Functionality

    /// Export all logs to a text file
    func exportLogs() throws -> URL {
        let timestamp = dateFormatter.string(from: Date()).replacingOccurrences(of: " ", with: "_")
        let filename = "hybrid_hr_bridge_logs_\(timestamp).txt"

        let tempDir = fileManager.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        // Build log content
        var content = """
        Hybrid HR Bridge - Debug Logs
        Generated: \(dateFormatter.string(from: Date()))
        Total Entries: \(logEntries.count)

        ========================================
        SYSTEM INFORMATION
        ========================================
        iOS Version: \(UIDevice.current.systemVersion)
        Device Model: \(UIDevice.current.model)
        Device Name: \(UIDevice.current.name)
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        Build Number: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")

        ========================================
        LOG ENTRIES
        ========================================

        """

        for entry in logEntries {
            content += entry.formattedMessage + "\n"
        }

        // Write to file
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        log(.info, category: "LogManager", message: "Logs exported to \(fileURL.path)")

        return fileURL
    }

    /// Export logs with statistical summary
    func exportLogsWithSummary() throws -> URL {
        let timestamp = dateFormatter.string(from: Date()).replacingOccurrences(of: " ", with: "_")
        let filename = "hybrid_hr_bridge_logs_detailed_\(timestamp).txt"

        let tempDir = fileManager.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        // Calculate statistics
        let errorCount = logEntries.filter { $0.level == .error }.count
        let warningCount = logEntries.filter { $0.level == .warning }.count
        let infoCount = logEntries.filter { $0.level == .info }.count
        let debugCount = logEntries.filter { $0.level == .debug }.count

        let categories = Dictionary(grouping: logEntries, by: { $0.category })
        let categorySummary = categories.map { key, value in
            "\(key): \(value.count) entries"
        }.joined(separator: "\n")

        // Build detailed content
        var content = """
        Hybrid HR Bridge - Detailed Debug Logs
        Generated: \(dateFormatter.string(from: Date()))

        ========================================
        SYSTEM INFORMATION
        ========================================
        iOS Version: \(UIDevice.current.systemVersion)
        Device Model: \(UIDevice.current.model)
        Device Name: \(UIDevice.current.name)
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        Build Number: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")

        ========================================
        LOG STATISTICS
        ========================================
        Total Entries: \(logEntries.count)

        By Level:
        - ERROR: \(errorCount)
        - WARNING: \(warningCount)
        - INFO: \(infoCount)
        - DEBUG: \(debugCount)

        By Category:
        \(categorySummary)

        ========================================
        RECENT ERRORS
        ========================================

        """

        // Add last 50 errors
        let recentErrors = logEntries.filter { $0.level == .error }.suffix(50)
        if recentErrors.isEmpty {
            content += "No errors recorded.\n"
        } else {
            for error in recentErrors {
                content += error.formattedMessage + "\n"
            }
        }

        content += """

        ========================================
        FULL LOG ENTRIES
        ========================================

        """

        for entry in logEntries {
            content += entry.formattedMessage + "\n"
        }

        // Write to file
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        log(.info, category: "LogManager", message: "Detailed logs exported to \(fileURL.path)")

        return fileURL
    }

    /// Clear all logs
    func clearLogs() {
        logEntries.removeAll()
        log(.info, category: "LogManager", message: "Logs cleared")
    }

    /// Get log summary for display
    func getLogSummary() -> String {
        let errorCount = logEntries.filter { $0.level == .error }.count
        let warningCount = logEntries.filter { $0.level == .warning }.count

        return "Total: \(logEntries.count) | Errors: \(errorCount) | Warnings: \(warningCount)"
    }
}
