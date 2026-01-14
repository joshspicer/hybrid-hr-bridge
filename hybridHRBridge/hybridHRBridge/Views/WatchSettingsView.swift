import SwiftUI

/// Watch settings and configuration view
struct WatchSettingsView: View {
    @EnvironmentObject var watchManager: WatchManager
    @State private var statusMessage: String?
    @State private var isSyncing = false
    
    var body: some View {
        List {
            // Watch Info Section
            if let watch = watchManager.connectedWatch {
                Section("Watch Information") {
                    LabeledContent("Name", value: watch.name)
                    
                    if let firmware = watch.firmwareVersion {
                        LabeledContent("Firmware", value: firmware)
                    }
                    
                    LabeledContent("Status") {
                        HStack {
                            Circle()
                                .fill(watchManager.authManager.isAuthenticated ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(watchManager.authManager.isAuthenticated ? "Authenticated" : "Not Authenticated")
                        }
                    }
                    
                    if let battery = watch.batteryStatus {
                        LabeledContent("Battery") {
                            HStack(spacing: 4) {
                                Text("\(battery.percentage)%")
                                if battery.isCharging {
                                    Image(systemName: "bolt.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            
            // Time Settings Section
            Section {
                Button {
                    syncTime()
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync Time")
                            Text("Update watch time to match phone")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated || isSyncing)
            } header: {
                Text("Time & Date")
            } footer: {
                Text("Sync your phone's time to the watch. Recommended after timezone changes.")
            }
            
            // Notification Settings Section
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
                
                if !watchManager.ancsAuthorized {
                    Button {
                        openBluetoothSettings()
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                                .frame(width: 30)
                            Text("Open Bluetooth Settings")
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ Notifications are not yet implemented.")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Fossil HR watches require proprietary notification forwarding. See documentation for details.")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            } header: {
                Text("Notifications")
            } footer: {
                if !watchManager.ancsAuthorized {
                    Text("Enable 'Share System Notifications' in iOS Bluetooth settings to authorize notification access.")
                } else {
                    Text("ANCS is authorized, but notification forwarding is not yet implemented.")
                }
            }
            
            // Device Management Section
            Section {
                Button(role: .destructive) {
                    disconnectWatch()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .frame(width: 30)
                        Text("Disconnect Watch")
                    }
                }
                .disabled(watchManager.connectedWatch == nil)
                
                Button(role: .destructive) {
                    forgetWatch()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .frame(width: 30)
                        Text("Forget Watch")
                    }
                }
                .disabled(watchManager.connectedWatch == nil)
            } header: {
                Text("Device Management")
            } footer: {
                Text("Disconnect to temporarily stop communication. Forget to remove the watch from saved devices.")
            }
            
            // Status Message
            if let message = statusMessage {
                Section {
                    Text(message)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            // About Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hybrid HR Bridge")
                        .font(.headline)
                    Text("iOS companion app for Fossil/Skagen Hybrid HR watches")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Label("Based on Gadgetbridge protocol", systemImage: "doc.text")
                        .font(.caption)
                    Label("Open source project", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                Link(destination: URL(string: "https://github.com/joshspicer/hybrid-hr-bridge")!) {
                    HStack {
                        Image(systemName: "link")
                            .frame(width: 30)
                        Text("View on GitHub")
                    }
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
    }
    
    // MARK: - Actions
    
    private func syncTime() {
        statusMessage = nil
        isSyncing = true
        
        Task {
            do {
                try await watchManager.syncTime()
                await MainActor.run {
                    statusMessage = "Time synced successfully"
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to sync time: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func openBluetoothSettings() {
        if let url = URL(string: "App-Prefs:root=Bluetooth") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
        // Alternative: Open general settings
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func disconnectWatch() {
        statusMessage = nil
        watchManager.disconnect()
        statusMessage = "Watch disconnected"
    }
    
    private func forgetWatch() {
        statusMessage = nil
        
        // Show confirmation
        guard let watch = watchManager.connectedWatch else { return }
        
        // Disconnect first
        watchManager.disconnect()
        
        // Remove from saved devices
        if let index = watchManager.savedDevices.firstIndex(where: { $0.id == watch.id }) {
            watchManager.savedDevices.remove(at: index)
            statusMessage = "Watch forgotten. It will no longer auto-reconnect."
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WatchSettingsView()
            .environmentObject({
                let manager = WatchManager()
                return manager
            }())
    }
}
