import SwiftUI
import UniformTypeIdentifiers

/// Detail view for a connected watch
struct DeviceDetailView: View {
    @EnvironmentObject var watchManager: WatchManager
    @StateObject private var logManager = LogManager.shared
    @State private var isSyncingTime = false
    @State private var showingAppInstall = false
    @State private var showingLogExport = false
    @State private var showingActivityData = false
    @State private var statusMessage: String?
    @State private var isRefreshingBattery = false
    @State private var isRefreshingActivity = false
    @State private var activityData: ActivityData?
    
    var body: some View {
        List {
            // Device Info Section
            if let watch = watchManager.connectedWatch {
                Section("Device") {
                    LabeledContent("Name", value: watch.name)
                    LabeledContent("Status") {
                        HStack {
                            Circle()
                                .fill(watchManager.authManager.isAuthenticated ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(watchManager.authManager.isAuthenticated ? "Authenticated" : "Not Authenticated")
                        }
                    }
                    if let firmware = watch.firmwareVersion {
                        LabeledContent("Firmware", value: firmware)
                    }
                }

                // Battery Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: batteryIcon(for: watch.batteryLevel))
                                    .foregroundColor(batteryColor(for: watch.batteryLevel))
                                    .font(.title2)
                                
                                if let battery = watch.batteryLevel {
                                    Text("\(battery)%")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                } else {
                                    Text("--")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let voltage = watch.batteryVoltageMillivolts {
                                let volts = Double(voltage) / 1000.0
                                Text(String(format: "%.3f V", volts))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            refreshBattery()
                        } label: {
                            if isRefreshingBattery {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!watchManager.authManager.isAuthenticated || isRefreshingBattery)
                    }
                } header: {
                    Text("Battery")
                }

                // Activity Summary Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        if let activity = activityData {
                            HStack(spacing: 20) {
                                VStack {
                                    Image(systemName: "figure.walk")
                                        .foregroundColor(.blue)
                                        .font(.title2)
                                    Text("\(activity.totalSteps)")
                                        .font(.headline)
                                    Text("Steps")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Divider()
                                    .frame(height: 40)
                                
                                VStack {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(.red)
                                        .font(.title2)
                                    Text(activity.averageHeartRate > 0 ? "\(activity.averageHeartRate)" : "--")
                                        .font(.headline)
                                    Text("Avg HR")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Divider()
                                    .frame(height: 40)
                                
                                VStack {
                                    Image(systemName: "flame.fill")
                                        .foregroundColor(.orange)
                                        .font(.title2)
                                    Text("\(activity.totalCalories)")
                                        .font(.headline)
                                    Text("Calories")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            HStack {
                                Image(systemName: "figure.walk.circle")
                                    .foregroundColor(.secondary)
                                    .font(.title2)
                                Text("No activity data")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Button {
                                refreshActivity()
                            } label: {
                                HStack {
                                    if isRefreshingActivity {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Refresh")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!watchManager.authManager.isAuthenticated || isRefreshingActivity)
                            
                            Spacer()
                            
                            if activityData != nil {
                                Button {
                                    showingActivityData = true
                                } label: {
                                    HStack {
                                        Text("View Details")
                                        Image(systemName: "chevron.right")
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Activity")
                }
            }
            
            // Quick Actions Section
            Section("Actions") {
                // Time Sync
                Button {
                    syncTime()
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .frame(width: 30)
                        Text("Sync Time")
                        Spacer()
                        if isSyncingTime {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated || isSyncingTime)
                
                // Install App
                Button {
                    showingAppInstall = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 30)
                        Text("Install Watch App")
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated)

                // Find Watch
                Button {
                    findWatch()
                } label: {
                    HStack {
                        Image(systemName: "ipad.and.iphone")
                            .frame(width: 30)
                        Text("Find Watch")
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated)
                
                // Music Control Test
                 Section("Music Control (Test)") {
                     Button {
                         updateTestTrack()
                     } label: {
                         HStack {
                             Image(systemName: "music.note")
                                 .frame(width: 30)
                             Text("Push 'Test Track' Info")
                         }
                     }
                     .disabled(!watchManager.authManager.isAuthenticated)
                     
                     HStack {
                         Spacer()
                         Button {
                             sendMusicCommand(.previous)
                         } label: {
                             Image(systemName: "backward.fill")
                                 .font(.title2)
                         }
                         .buttonStyle(.borderless)
                         
                         Spacer()
                         
                         Button {
                             sendMusicCommand(.playPause)
                         } label: {
                             Image(systemName: "playpause.fill")
                                 .font(.title2)
                         }
                         .buttonStyle(.borderless)
                         
                         Spacer()
                         
                         Button {
                             sendMusicCommand(.next)
                         } label: {
                             Image(systemName: "forward.fill")
                                 .font(.title2)
                         }
                         .buttonStyle(.borderless)
                         Spacer()
                     }
                     .padding(.vertical, 8)
                     .disabled(!watchManager.authManager.isAuthenticated)
                 }

                // Export Logs
                Button {
                    showingLogExport = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .frame(width: 30)
                        VStack(alignment: .leading) {
                            Text("Export Debug Logs")
                            Text(logManager.getLogSummary())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Notification Status Section
            Section {
                HStack {
                    Text("ANCS Authorized")
                    Spacer()
                    HStack {
                        Circle()
                            .fill(watchManager.ancsAuthorized ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(watchManager.ancsAuthorized ? "Yes" : "No")
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚠️ Notifications are not yet implemented.")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Fossil HR watches require proprietary notification forwarding (not standard ANCS). See docs/NOTIFICATION_RESEARCH.md for details.")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Research on notification protocol is documented but not yet functional.")
            }
            
            // Status Message
            if let message = statusMessage {
                Section {
                    Text(message)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            // Transfer Progress
            if watchManager.fileTransferManager.isTransferring {
                Section("Transfer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transferring...")
                            .font(.caption)
                        ProgressView(value: watchManager.fileTransferManager.progress)
                        Text("\(Int(watchManager.fileTransferManager.progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Authentication Section (if not authenticated)
            if !watchManager.authManager.isAuthenticated {
                Section {
                    Button("Authenticate") {
                        authenticate()
                    }
                } footer: {
                    Text("Authentication is required for time sync, activity data, and battery status. Notifications work without authentication!")
                }
            }
        }
        .navigationTitle("Watch")
        .sheet(isPresented: $showingAppInstall) {
            AppInstallView()
        }
        .sheet(isPresented: $showingLogExport) {
            LogExportView()
                .environmentObject(logManager)
        }
        .sheet(isPresented: $showingActivityData) {
            NavigationStack {
                ActivityDataView()
                    .environmentObject(watchManager)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingActivityData = false
                            }
                        }
                    }
            }
        }
    }
    
    private func syncTime() {
        isSyncingTime = true
        statusMessage = nil
        
        Task {
            do {
                try await watchManager.syncTime()
                statusMessage = "Time synced successfully"
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
            isSyncingTime = false
        }
    }

    private func refreshBattery() {
        statusMessage = nil
        isRefreshingBattery = true
        
        LogManager.shared.info("UI", "Battery refresh button tapped")

        Task {
            do {
                LogManager.shared.info("UI", "Starting battery refresh...")
                let status = try await watchManager.refreshBatteryStatus()
                await MainActor.run {
                    statusMessage = "Battery: \(status.percentage)%"
                    LogManager.shared.info("UI", "Battery refresh complete: \(status.percentage)%")
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Battery update failed: \(error.localizedDescription)"
                    LogManager.shared.error("UI", "Battery refresh failed: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isRefreshingBattery = false
            }
        }
    }

    private func refreshActivity() {
        statusMessage = nil
        isRefreshingActivity = true

        Task {
            do {
                let data = try await watchManager.fetchActivityData()
                await MainActor.run {
                    activityData = data
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Activity fetch failed: \(error.localizedDescription)"
                }
            }

            await MainActor.run {
                isRefreshingActivity = false
            }
        }
    }

    // MARK: - Battery Helpers

    private func batteryIcon(for level: Int?) -> String {
        guard let level = level else { return "battery.0" }
        switch level {
        case 0..<10: return "battery.0"
        case 10..<35: return "battery.25"
        case 35..<65: return "battery.50"
        case 65..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryColor(for level: Int?) -> Color {
        guard let level = level else { return .secondary }
        switch level {
        case 0..<20: return .red
        case 20..<40: return .orange
        default: return .green
        }
    }
    
    private func authenticate() {
        Task {
            do {
                try await watchManager.authenticate()
                statusMessage = "Authenticated successfully"
            } catch {
                statusMessage = "Auth failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func findWatch() {
        statusMessage = "Sending vibration..."
        Task {
            do {
                try await watchManager.findWatch()
                statusMessage = "Watch should be vibrating"
            } catch {
                statusMessage = "Find device failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func sendMusicCommand(_ command: MusicControlManager.MusicCommand) {
        Task {
            do {
                try await watchManager.sendMusicCommand(command)
                statusMessage = "Sent music command: \(command)"
            } catch {
                statusMessage = "Music command failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func updateTestTrack() {
        Task {
            do {
                try await watchManager.updateMusicInfo(
                    artist: "Test Artist",
                    album: "Test Album",
                    title: "Test Track 1"
                )
                statusMessage = "Updated track info"
            } catch {
                statusMessage = "Update track failed: \(error.localizedDescription)"
            }
        }
    }
}

/// View for installing watch apps
struct AppInstallView: View {
    @EnvironmentObject var watchManager: WatchManager
    @Environment(\.dismiss) var dismiss
    
    @State private var isImporting = false
    @State private var isInstalling = false
    @State private var statusMessage: String?
    @State private var selectedFileURL: URL?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isImporting = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text("Select .wapp File")
                        }
                    }
                    
                    if let url = selectedFileURL {
                        LabeledContent("Selected", value: url.lastPathComponent)
                    }
                } footer: {
                    Text("Select a .wapp file to install on your watch. You can build custom apps using the Fossil HR SDK.")
                }
                
                if selectedFileURL != nil {
                    Section {
                        Button {
                            installApp()
                        } label: {
                            HStack {
                                Spacer()
                                if isInstalling {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text("Install")
                                Spacer()
                            }
                        }
                        .disabled(isInstalling)
                    }
                }
                
                if watchManager.fileTransferManager.isTransferring {
                    Section("Progress") {
                        ProgressView(value: watchManager.fileTransferManager.progress)
                        Text("\(Int(watchManager.fileTransferManager.progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let message = statusMessage {
                    Section {
                        Text(message)
                            .foregroundColor(message.contains("Success") ? .green : .red)
                    }
                }
                
                Section {
                    Link(destination: URL(string: "https://github.com/dakhnod/Fossil-HR-SDK")!) {
                        HStack {
                            Image(systemName: "link")
                            Text("Fossil HR SDK on GitHub")
                        }
                    }
                } header: {
                    Text("Resources")
                } footer: {
                    Text("Use the Fossil HR SDK to build custom watch faces and apps.")
                }
            }
            .navigationTitle("Install App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        selectedFileURL = url
                    }
                case .failure(let error):
                    statusMessage = "Failed to select file: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func installApp() {
        guard let url = selectedFileURL else { return }
        
        isInstalling = true
        statusMessage = nil
        
        Task {
            do {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    statusMessage = "Cannot access file"
                    isInstalling = false
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                try await watchManager.installApp(from: url)
                statusMessage = "Success! App installed."
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
            isInstalling = false
        }
    }
}

/// View for exporting debug logs
struct LogExportView: View {
    @EnvironmentObject var logManager: LogManager
    @Environment(\.dismiss) var dismiss

    @State private var isExporting = false
    @State private var statusMessage: String?
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Log Statistics") {
                    Text(logManager.getLogSummary())
                        .font(.callout)
                }

                Section {
                    Button {
                        exportLogs(detailed: false)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Export Basic Logs")
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isExporting)

                    Button {
                        exportLogs(detailed: true)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("Export Detailed Logs")
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isExporting)
                } header: {
                    Text("Export Options")
                } footer: {
                    Text("Detailed logs include statistics and a summary of errors. Share these logs with developers to help debug connection issues.")
                }

                if let message = statusMessage {
                    Section {
                        Text(message)
                            .foregroundColor(message.contains("Success") ? .green : .red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        logManager.clearLogs()
                        statusMessage = "Logs cleared"
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Logs")
                        }
                    }
                } footer: {
                    Text("Clear logs to free up memory. Make sure to export first if you need them.")
                }
            }
            .navigationTitle("Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func exportLogs(detailed: Bool) {
        isExporting = true
        statusMessage = nil

        Task {
            do {
                let url = detailed
                    ? try logManager.exportLogsWithSummary()
                    : try logManager.exportLogs()

                exportedFileURL = url
                statusMessage = "Success! Logs exported to \(url.lastPathComponent)"

                // Show share sheet
                await MainActor.run {
                    showShareSheet = true
                }
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }
}

/// UIKit share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        DeviceDetailView()
            .environmentObject(WatchManager())
    }
}
