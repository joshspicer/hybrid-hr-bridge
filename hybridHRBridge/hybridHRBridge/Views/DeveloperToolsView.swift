import SwiftUI

/// Developer tools and diagnostic information
struct DeveloperToolsView: View {
    @EnvironmentObject var watchManager: WatchManager
    @State private var statusMessage: String?
    @State private var showingCharacteristics = false
    @State private var showingDeviceInfo = false
    
    var body: some View {
        List {
            // Connection Diagnostics
            Section {
                LabeledContent("Bluetooth State") {
                    Text(bluetoothStateString)
                        .foregroundColor(bluetoothStateColor)
                }
                
                LabeledContent("Connection State") {
                    Text(connectionStateString)
                        .foregroundColor(connectionStateColor)
                }
                
                if watchManager.authManager.isAuthenticated {
                    LabeledContent("Auth Status") {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Authenticated")
                        }
                    }
                }
                
                Button {
                    showingCharacteristics = true
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                            .frame(width: 30)
                        Text("View BLE Characteristics")
                    }
                }
            } header: {
                Text("Connection Status")
            }
            
            // Protocol Information
            Section {
                LabeledContent("Service UUID") {
                    Text("3dda0001-957f...")
                        .font(.system(.caption, design: .monospaced))
                }
                
                LabeledContent("File Handles") {
                    Text("22 defined")
                }
                
                LabeledContent("Characteristics") {
                    Text("7 required")
                }
            } header: {
                Text("Protocol Info")
            } footer: {
                Text("Fossil/Skagen Hybrid HR proprietary BLE protocol based on Gadgetbridge reverse engineering")
            }
            
            // Device Info
            if let watch = watchManager.connectedWatch {
                Section {
                    LabeledContent("Device UUID") {
                        Text(watch.id.uuidString.prefix(13) + "...")
                            .font(.system(.caption, design: .monospaced))
                    }
                    
                    if let firmware = watchManager.deviceInfoManager.firmwareVersion {
                        LabeledContent("Firmware") {
                            Text(firmware)
                        }
                    }
                    
                    if let model = watchManager.deviceInfoManager.modelNumber {
                        LabeledContent("Model") {
                            Text(model)
                        }
                    }
                    
                    if let serial = watchManager.deviceInfoManager.serialNumber {
                        LabeledContent("Serial") {
                            Text(serial)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    
                    Button {
                        showingDeviceInfo = true
                    } label: {
                        HStack {
                            Image(systemName: "info.circle")
                                .frame(width: 30)
                            Text("Detailed Device Info")
                        }
                    }
                } header: {
                    Text("Device Information")
                }
            }
            
            // Test Actions
            Section {
                Button {
                    testVibration()
                } label: {
                    HStack {
                        Image(systemName: "ipad.and.iphone")
                            .frame(width: 30)
                        Text("Test Vibration")
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated)
                
                Button {
                    testMusicInfo()
                } label: {
                    HStack {
                        Image(systemName: "music.note")
                            .frame(width: 30)
                        Text("Test Music Info")
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated)
            } header: {
                Text("Test Commands")
            } footer: {
                Text("Send test commands to verify protocol implementation")
            }
            
            // Status Message
            if let message = statusMessage {
                Section {
                    Text(message)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Developer Tools")
        .sheet(isPresented: $showingCharacteristics) {
            CharacteristicsView()
                .environmentObject(watchManager)
        }
        .sheet(isPresented: $showingDeviceInfo) {
            DeviceInfoDetailView()
                .environmentObject(watchManager)
        }
    }
    
    // MARK: - Computed Properties
    
    private var bluetoothStateString: String {
        switch watchManager.bluetoothManager.bluetoothState {
        case .poweredOn: return "Powered On"
        case .poweredOff: return "Powered Off"
        case .unauthorized: return "Unauthorized"
        case .unsupported: return "Unsupported"
        case .resetting: return "Resetting"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
    
    private var bluetoothStateColor: Color {
        switch watchManager.bluetoothManager.bluetoothState {
        case .poweredOn: return .green
        case .poweredOff: return .red
        case .unauthorized: return .orange
        default: return .secondary
        }
    }
    
    private var connectionStateString: String {
        switch watchManager.connectionStatus {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .authenticating: return "Authenticating"
        case .connected: return "Connected"
        }
    }
    
    private var connectionStateColor: Color {
        switch watchManager.connectionStatus {
        case .connected: return .green
        case .authenticating, .connecting: return .orange
        case .scanning: return .blue
        case .disconnected: return .secondary
        }
    }
    
    // MARK: - Actions
    
    private func testVibration() {
        statusMessage = "Sending vibration..."
        Task {
            do {
                try await watchManager.findWatch()
                await MainActor.run {
                    statusMessage = "✅ Vibration sent"
                }
            } catch {
                await MainActor.run {
                    statusMessage = "❌ Failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func testMusicInfo() {
        statusMessage = "Sending test music info..."
        Task {
            do {
                try await watchManager.updateMusicInfo(
                    artist: "Test Artist",
                    album: "Test Album",
                    title: "Test Track"
                )
                await MainActor.run {
                    statusMessage = "✅ Music info sent"
                }
            } catch {
                await MainActor.run {
                    statusMessage = "❌ Failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Characteristics View

private struct CharacteristicsView: View {
    @EnvironmentObject var watchManager: WatchManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Required Characteristics") {
                    ForEach(FossilConstants.allCharacteristics, id: \.self) { uuid in
                        CharacteristicRow(
                            uuid: uuid,
                            isDiscovered: watchManager.bluetoothManager.connectedDevice?.characteristics[uuid] != nil
                        )
                    }
                }
            }
            .navigationTitle("BLE Characteristics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct CharacteristicRow: View {
    let uuid: CBUUID
    let isDiscovered: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(characteristicName)
                    .font(.subheadline)
                Text(uuid.uuidString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(isDiscovered ? Color.green : Color.red)
                .frame(width: 8, height: 8)
        }
    }
    
    private var characteristicName: String {
        switch uuid {
        case FossilConstants.characteristicConnection: return "Connection"
        case FossilConstants.characteristicFileOps: return "File Operations"
        case FossilConstants.characteristicFileData: return "File Data"
        case FossilConstants.characteristicAuthentication: return "Authentication"
        case FossilConstants.characteristicEvents: return "Events"
        case FossilConstants.characteristicHeartRate: return "Heart Rate"
        default: return "Unknown"
        }
    }
}

// MARK: - Device Info Detail View

private struct DeviceInfoDetailView: View {
    @EnvironmentObject var watchManager: WatchManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if let firmware = watchManager.deviceInfoManager.firmwareVersion {
                    infoRow(title: "Firmware Version", value: firmware)
                }
                
                if let hardware = watchManager.deviceInfoManager.hardwareVersion {
                    infoRow(title: "Hardware Version", value: hardware)
                }
                
                if let software = watchManager.deviceInfoManager.softwareVersion {
                    infoRow(title: "Software Version", value: software)
                }
                
                if let manufacturer = watchManager.deviceInfoManager.manufacturerName {
                    infoRow(title: "Manufacturer", value: manufacturer)
                }
                
                if let model = watchManager.deviceInfoManager.modelNumber {
                    infoRow(title: "Model Number", value: model)
                }
                
                if let serial = watchManager.deviceInfoManager.serialNumber {
                    infoRow(title: "Serial Number", value: serial)
                }
                
                if watchManager.deviceInfoManager.isHRModel() {
                    Section {
                        Label("This is a Hybrid HR model", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Device Info")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func infoRow(title: String, value: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeveloperToolsView()
            .environmentObject({
                let manager = WatchManager()
                return manager
            }())
    }
}
