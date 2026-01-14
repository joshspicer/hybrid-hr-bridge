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
    @State private var showingHeartRate = false
    @State private var showingAlarms = false
    @State private var showingSettings = false
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

                // Battery Section - Using Component
                BatteryStatusView(
                    watch: watch,
                    isRefreshing: isRefreshingBattery,
                    isAuthenticated: watchManager.authManager.isAuthenticated,
                    onRefresh: refreshBattery
                )

                // Activity Summary Section - Using Component
                ActivitySummaryView(
                    activityData: activityData,
                    isRefreshing: isRefreshingActivity,
                    isAuthenticated: watchManager.authManager.isAuthenticated,
                    onRefresh: refreshActivity,
                    onViewDetails: { showingActivityData = true }
                )
            }

            // Quick Actions Section - Using Component
            DeviceActionsView(
                isAuthenticated: watchManager.authManager.isAuthenticated,
                isSyncingTime: isSyncingTime,
                onSyncTime: syncTime,
                onInstallApp: { showingAppInstall = true },
                onFindWatch: findWatch,
                onUpdateTestTrack: updateTestTrack,
                onSendMusicCommand: sendMusicCommand,
                onExportLogs: { showingLogExport = true },
                onHeartRate: { showingHeartRate = true },
                onAlarms: { showingAlarms = true },
                onSettings: { showingSettings = true },
                logSummary: logManager.getLogSummary()
            )

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
        .sheet(isPresented: $showingHeartRate) {
            NavigationStack {
                HeartRateView()
                    .environmentObject(watchManager)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingHeartRate = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingAlarms) {
            NavigationStack {
                AlarmListView()
                    .environmentObject(watchManager)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingAlarms = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                WatchSettingsView()
                    .environmentObject(watchManager)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Action Methods

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
