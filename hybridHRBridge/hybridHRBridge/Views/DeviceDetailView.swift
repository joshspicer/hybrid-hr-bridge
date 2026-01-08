import SwiftUI
import UniformTypeIdentifiers

/// Detail view for a connected watch
struct DeviceDetailView: View {
    @EnvironmentObject var watchManager: WatchManager
    @State private var showingNotificationTest = false
    @State private var isSyncingTime = false
    @State private var showingAppInstall = false
    @State private var statusMessage: String?
    
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
                    if let battery = watch.batteryLevel {
                        LabeledContent("Battery", value: "\(battery)%")
                    }
                    if let firmware = watch.firmwareVersion {
                        LabeledContent("Firmware", value: firmware)
                    }
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
                
                // Test Notification
                Button {
                    showingNotificationTest = true
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                            .frame(width: 30)
                        Text("Send Test Notification")
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated)
                
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
                    Text("Authentication is required to send notifications and sync data.")
                }
            }
        }
        .navigationTitle("Watch")
        .sheet(isPresented: $showingNotificationTest) {
            TestNotificationView()
        }
        .sheet(isPresented: $showingAppInstall) {
            AppInstallView()
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
}

/// View for sending test notifications
struct TestNotificationView: View {
    @EnvironmentObject var watchManager: WatchManager
    @Environment(\.dismiss) var dismiss
    
    @State private var title = "Test Notification"
    @State private var sender = "Hybrid HR Bridge"
    @State private var message = "Hello from iOS!"
    @State private var selectedType: NotificationType = .notification
    @State private var isSending = false
    @State private var statusMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Notification") {
                    TextField("Title", text: $title)
                    TextField("Sender", text: $sender)
                    TextField("Message", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Type") {
                    Picker("Type", selection: $selectedType) {
                        Text("Notification").tag(NotificationType.notification)
                        Text("Text").tag(NotificationType.text)
                        Text("Email").tag(NotificationType.email)
                        Text("Calendar").tag(NotificationType.calendar)
                        Text("Call").tag(NotificationType.incomingCall)
                    }
                }
                
                Section {
                    Button {
                        sendNotification()
                    } label: {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Send")
                            Spacer()
                        }
                    }
                    .disabled(isSending || title.isEmpty)
                }
                
                if let message = statusMessage {
                    Section {
                        Text(message)
                            .foregroundColor(message.contains("Success") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Test Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func sendNotification() {
        isSending = true
        statusMessage = nil
        
        Task {
            do {
                try await watchManager.sendNotification(
                    type: selectedType,
                    title: title,
                    sender: sender,
                    message: message,
                    appIdentifier: "com.hybridhrbridge.test"
                )
                statusMessage = "Success! Check your watch."
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
            isSending = false
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

#Preview {
    NavigationStack {
        DeviceDetailView()
            .environmentObject(WatchManager())
    }
}
