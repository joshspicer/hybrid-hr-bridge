import Foundation

/// Collects in-app logs and allows exporting them to a text file.
final class BridgeLogger {
    static let shared = BridgeLogger()
    
    private let queue = DispatchQueue(label: "com.hybridhrbridge.logger")
    private var entries: [String] = []
    private let timestampFormatter: ISO8601DateFormatter
    private let fileDateFormatter: DateFormatter
    
    private init() {
        timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyyMMdd-HHmmss"
    }
    
    /// Append a log entry and mirror it to the console.
    func log(_ message: String) {
        queue.async {
            let entry = "[\(self.timestampFormatter.string(from: Date()))] \(message)"
            print(entry)
            self.entries.append(entry)
            
            if self.entries.count > 2000 {
                self.entries.removeFirst(self.entries.count - 2000)
            }
        }
    }
    
    /// Export collected logs to a temporary text file and return its URL.
    func exportLogFile() throws -> URL {
        let snapshot: [String] = queue.sync { entries }
        let logText = snapshot.joined(separator: "\n")
        let filename = "HybridHRBridge-logs-\(fileDateFormatter.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try logText.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    /// Whether any logs have been collected.
    func hasLogs() -> Bool {
        queue.sync { !entries.isEmpty }
    }
}
