import SwiftUI

/// Main view showing discovered and saved watches
struct DeviceListView: View {
    @EnvironmentObject var watchManager: WatchManager
    @State private var showingKeyInput = false
    @State private var selectedDeviceId: UUID?
    @State private var secretKeyInput = ""
    
    var body: some View {
        NavigationStack {
            List {
                // Connection Status Section
                Section {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)
                        Text(watchManager.connectionStatus.displayText)
                            .foregroundColor(.secondary)
                        Spacer()
                        if watchManager.connectionStatus == .scanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                
                // Connected Device Section
                if let watch = watchManager.connectedWatch {
                    Section("Connected") {
                        NavigationLink {
                            DeviceDetailView()
                        } label: {
                            HStack {
                                Image(systemName: "applewatch")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(watch.name)
                                        .font(.headline)
                                    if watchManager.authManager.isAuthenticated {
                                        Text("Authenticated")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Not authenticated")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                        
                        Button("Disconnect", role: .destructive) {
                            watchManager.disconnect()
                        }
                    }
                }
                
                // Saved Devices Section
                if !watchManager.savedDevices.isEmpty {
                    Section("Saved Devices") {
                        ForEach(watchManager.savedDevices) { device in
                            HStack {
                                Image(systemName: "applewatch")
                                    .foregroundColor(.gray)
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    if device.secretKey != nil {
                                        Text("Key configured")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Key required")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                                Spacer()
                                
                                Menu {
                                    Button("Set Secret Key") {
                                        selectedDeviceId = device.id
                                        secretKeyInput = device.secretKey ?? ""
                                        showingKeyInput = true
                                    }
                                    Button("Remove", role: .destructive) {
                                        watchManager.removeSavedDevice(device.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                    }
                }
                
                // Discovered Devices Section
                if !watchManager.discoveredDevices.isEmpty {
                    Section("Discovered") {
                        ForEach(watchManager.discoveredDevices) { device in
                            Button {
                                watchManager.saveDevice(device)
                                watchManager.connect(to: device)
                            } label: {
                                HStack {
                                    Image(systemName: "applewatch")
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading) {
                                        Text(device.name)
                                            .foregroundColor(.primary)
                                        Text("RSSI: \(device.rssi) dBm")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // Error Section
                if let error = watchManager.lastError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Text(error.localizedDescription)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Hybrid HR Bridge")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if watchManager.bluetoothManager.isScanning {
                            watchManager.stopScanning()
                        } else {
                            watchManager.startScanning()
                        }
                    } label: {
                        Image(systemName: watchManager.bluetoothManager.isScanning ? "stop.fill" : "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $showingKeyInput) {
                SecretKeyInputView(
                    deviceId: selectedDeviceId,
                    keyInput: $secretKeyInput,
                    isPresented: $showingKeyInput
                )
                .environmentObject(watchManager)
            }
        }
    }
    
    private var statusColor: Color {
        switch watchManager.connectionStatus {
        case .disconnected: return .red
        case .scanning: return .orange
        case .connecting, .authenticating: return .yellow
        case .connected: return .green
        }
    }
}

/// View for entering/editing secret key
struct SecretKeyInputView: View {
    let deviceId: UUID?
    @Binding var keyInput: String
    @Binding var isPresented: Bool
    @EnvironmentObject var watchManager: WatchManager
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Secret Key (32 hex characters)", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Device Secret Key")
                } footer: {
                    Text("Enter the 16-byte (32 hex character) secret key from Gadgetbridge export. This key is required for authentication.")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Text("To get your key from Gadgetbridge:")
                        .font(.headline)
                    Text("1. Open Gadgetbridge on Android")
                    Text("2. Long-press your watch")
                    Text("3. Tap the gear icon (Settings)")
                    Text("4. Find 'Auth Key' and copy it")
                }
            }
            .navigationTitle("Secret Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveKey()
                    }
                    .disabled(keyInput.count != 32)
                }
            }
        }
    }
    
    private func saveKey() {
        guard let deviceId = deviceId else { return }
        
        do {
            try watchManager.setSecretKey(keyInput, for: deviceId)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    DeviceListView()
        .environmentObject(WatchManager())
}
