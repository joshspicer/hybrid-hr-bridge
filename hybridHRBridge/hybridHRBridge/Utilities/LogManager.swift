import Foundation
import Combine
import UIKit
import os.log
import InnerLoop

/// Custom log destination that captures logs for in-app viewing
class InAppLogDestination: LogDestination {
    weak var logManager: LogManager?
    
    nonisolated func write(message: String, level: LogLevel, category: String?, timestamp: Date, file: String, function: String, line: Int) {
        Task { @MainActor in
            logManager?.addEntry(
                timestamp: timestamp,
                levelRaw: level.rawValue,
                category: category ?? "App",
                message: message
            )
        }
    }
}

/// Centralized logging manager with file export capability
/// Captures all app logs for debugging connection and authentication issues
/// Now powered by InnerLoop library for remote logging and shake-to-report features
@MainActor
final class LogManager: ObservableObject {

    // MARK: - Singleton

    static let shared = LogManager()

    // MARK: - Properties

    @Published private(set) var logEntries: [LogEntry] = []
    private let maxLogEntries = 5000  // Keep last 5000 entries in memory
    
    private let inAppDestination = InAppLogDestination()

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
        let level: AppLogLevel
        let category: String
        let message: String

        var formattedMessage: String {
            let dateStr = ISO8601DateFormatter().string(from: timestamp)
            return "[\(dateStr)] [\(level.rawValue)] [\(category)] \(message)"
        }
    }

    /// Local LogLevel enum to avoid naming collision with InnerLoop.LogLevel
    enum AppLogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        /// Initialize from InnerLoop.LogLevel rawValue (Int)
        init(fromRawValue rawValue: Int) {
            switch rawValue {
            case 0: self = .debug
            case 1: self = .info
            case 2: self = .warning
            case 3: self = .error
            default: self = .info
            }
        }
    }

    // MARK: - Initialization

    private init() {
        // Set up InnerLoop with our custom destination for in-app viewing
        inAppDestination.logManager = self
        
        // Configure InnerLoop (shake gesture enabled for debug builds)
        // Note: appId and sharedSecret are required but we use placeholders for local-only logging
        let bundleId = Bundle.main.bundleIdentifier ?? "com.hybridhrbridge"
        let config = InnerLoopConfiguration(
            appId: bundleId,
            sharedSecret: "local-only",  // Not sending to remote server
            enableShakeGesture: true,
            environment: "development",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
        InnerLoop.shared.initialize(with: config)
        
        // Add our custom destination to capture logs for in-app viewing
        InnerLoop.shared.logger.addDestination(inAppDestination)
        
        InnerLoop.shared.info("LogManager", "LogManager initialized with InnerLoop")
    }
    
    // MARK: - Internal Methods
    
    /// Add a log entry to the in-app buffer (called by InAppLogDestination)
    /// Uses raw Int value to avoid type collision with InnerLoop.LogLevel
    fileprivate func addEntry(timestamp: Date, levelRaw: Int, category: String, message: String) {
        let entry = LogEntry(
            timestamp: timestamp,
            level: AppLogLevel(fromRawValue: levelRaw),
            category: category,
            message: message
        )
        
        logEntries.append(entry)
        
        // Trim if exceeds max
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
        
        // Log to system logger for crash reports
        let osLog = OSLog(subsystem: "com.hybridhrbridge", category: category)
        switch entry.level {
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

    // MARK: - Logging Methods

    func log(_ level: AppLogLevel, category: String, message: String) {
        // Forward to InnerLoop
        switch level {
        case .debug:
            InnerLoop.shared.debug(category, message)
        case .info:
            InnerLoop.shared.info(category, message)
        case .warning:
            InnerLoop.shared.warning(category, message)
        case .error:
            InnerLoop.shared.error(category, message)
        }
    }

    // Convenience methods - forward to InnerLoop
    func debug(_ category: String, _ message: String) {
        InnerLoop.shared.debug(category, message)
    }

    func info(_ category: String, _ message: String) {
        InnerLoop.shared.info(category, message)
    }

    func warning(_ category: String, _ message: String) {
        InnerLoop.shared.warning(category, message)
    }

    func error(_ category: String, _ message: String) {
        InnerLoop.shared.error(category, message)
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

        InnerLoop.shared.info("LogManager", "Logs exported to \(fileURL.path)")

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

        InnerLoop.shared.info("LogManager", "Detailed logs exported to \(fileURL.path)")

        return fileURL
    }

    /// Clear all logs
    func clearLogs() {
        logEntries.removeAll()
        InnerLoop.shared.info("LogManager", "Logs cleared")
    }

    /// Get log summary for display
    func getLogSummary() -> String {
        let errorCount = logEntries.filter { $0.level == .error }.count
        let warningCount = logEntries.filter { $0.level == .warning }.count

        return "Total: \(logEntries.count) | Errors: \(errorCount) | Warnings: \(warningCount)"
    }
}
