import SwiftUI

/// Debug view with manual controls for testing and development
struct DebugView: View {
    @EnvironmentObject var watchManager: WatchManager
    @StateObject private var logManager = LogManager.shared
    @State private var statusMessage: String?
    @State private var isPerformingAction = false

    var body: some View {
        List {
            // Connection State Section
            Section("Connection State") {
                LabeledContent("BLE State") {
                    Text(bluetoothStateText)
                        .foregroundColor(bluetoothStateColor)
                }

                LabeledContent("Connection") {
                    Text(watchManager.connectionStatus.displayText)
                        .foregroundColor(connectionColor)
                }

                LabeledContent("Authenticated") {
                    HStack {
                        Circle()
                            .fill(watchManager.authManager.isAuthenticated ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(watchManager.authManager.isAuthenticated ? "Yes" : "No")
                    }
                }

                if let watch = watchManager.connectedWatch {
                    LabeledContent("Device Name", value: watch.name)
                    LabeledContent("Device ID", value: watch.id.uuidString.prefix(8).description)

                    if let key = watch.secretKey {
                        LabeledContent("Secret Key") {
                            Text(key.prefix(8).description + "...")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            // Connection Controls
            Section("Connection Controls") {
                Button {
                    watchManager.startScanning()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Start Scanning")
                        Spacer()
                        if watchManager.connectionStatus == .scanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(watchManager.connectionStatus == .scanning)

                Button {
                    watchManager.stopScanning()
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop Scanning")
                    }
                }
                .disabled(watchManager.connectionStatus != .scanning)

                Button {
                    performAction {
                        try await watchManager.authenticate()
                        statusMessage = "✅ Authentication successful"
                    }
                } label: {
                    HStack {
                        Image(systemName: "key.fill")
                        Text("Authenticate")
                        Spacer()
                        if isPerformingAction {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(!canAuthenticate || isPerformingAction)

                Button(role: .destructive) {
                    watchManager.disconnect()
                    statusMessage = "Disconnected"
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Disconnect")
                    }
                }
                .disabled(watchManager.connectedWatch == nil)
            }

            // Test Actions
            Section("Test Actions") {
                Button {
                    performAction {
                        try await watchManager.syncTime()
                        statusMessage = "✅ Time synced"
                    }
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Sync Time")
                        Spacer()
                        if isPerformingAction {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated || isPerformingAction)

                Button {
                    performAction {
                        try await watchManager.sendNotification(
                            type: .notification,
                            title: "Debug Test",
                            sender: "Hybrid HR Bridge",
                            message: "Test notification from debug view",
                            appIdentifier: "com.hybridhrbridge.debug"
                        )
                        statusMessage = "✅ Test notification sent"
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Send Test Notification")
                        Spacer()
                        if isPerformingAction {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated || isPerformingAction)
            }

            // Logs Section
            Section("Debug Logs") {
                LabeledContent("Total Entries") {
                    Text("\(logManager.getAllLogs().count)")
                        .font(.system(.body, design: .monospaced))
                }

                Button {
                    logManager.clearLogs()
                    statusMessage = "Logs cleared"
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Logs")
                    }
                }

                NavigationLink {
                    LogExportView()
                        .environmentObject(logManager)
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("View/Export Logs")
                    }
                }
            }

            // Status Message
            if let message = statusMessage {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(message.contains("✅") ? .green : (message.contains("❌") ? .red : .secondary))
                }
            }

            // Developer Info
            Section("Developer Info") {
                LabeledContent("Bluetooth MTU") {
                    Text("~180 bytes")
                        .font(.system(.caption, design: .monospaced))
                }

                LabeledContent("Protocol Version") {
                    Text("Fossil Hybrid HR")
                        .font(.caption)
                }

                Link(destination: URL(string: "https://codeberg.org/Freeyourgadget/Gadgetbridge")!) {
                    HStack {
                        Image(systemName: "link")
                        Text("Gadgetbridge Source")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bluetoothStateText: String {
        switch watchManager.bluetoothManager.centralManager?.state {
        case .poweredOn:
            return "Powered On"
        case .poweredOff:
            return "Powered Off"
        case .resetting:
            return "Resetting"
        case .unauthorized:
            return "Unauthorized"
        case .unsupported:
            return "Unsupported"
        case .unknown:
            return "Unknown"
        case nil:
            return "Not Ready"
        @unknown default:
            return "Unknown"
        }
    }

    private var bluetoothStateColor: Color {
        guard let state = watchManager.bluetoothManager.centralManager?.state else {
            return .gray
        }

        switch state {
        case .poweredOn:
            return .green
        case .poweredOff, .unauthorized, .unsupported:
            return .red
        default:
            return .orange
        }
    }

    private var connectionColor: Color {
        switch watchManager.connectionStatus {
        case .connected:
            return .green
        case .connecting, .authenticating, .scanning:
            return .orange
        case .disconnected:
            return .gray
        }
    }

    private var canAuthenticate: Bool {
        watchManager.connectedWatch != nil &&
        watchManager.connectedWatch?.secretKey != nil &&
        !watchManager.authManager.isAuthenticated
    }

    private func performAction(_ action: @escaping () async throws -> Void) {
        isPerformingAction = true
        statusMessage = nil

        Task {
            do {
                try await action()
            } catch {
                statusMessage = "❌ Error: \(error.localizedDescription)"
            }
            isPerformingAction = false
        }
    }
}

#Preview {
    NavigationStack {
        DebugView()
            .environmentObject(WatchManager())
    }
}
