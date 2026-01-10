import SwiftUI

/// View for configuring and installing the custom text display app
struct CustomTextAppView: View {
    @EnvironmentObject var watchManager: WatchManager
    @Environment(\.dismiss) var dismiss
    
    @State private var customText: String = "Hello!"
    @State private var isInstalling = false
    @State private var statusMessage: String?
    @State private var messageType: MessageType = .info
    
    private let maxTextLength = 20
    private let logger = LogManager.shared
    
    enum MessageType {
        case info, success, error
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .error: return .red
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "textformat.size.larger")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Custom Text Display")
                                .font(.headline)
                            Text("A simple app that displays your text on the watch")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Display Text")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(customText.count)/\(maxTextLength)")
                                .font(.caption)
                                .foregroundColor(customText.count > maxTextLength ? .red : .secondary)
                        }
                        
                        TextField("Enter text", text: $customText)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        
                        if customText.count > maxTextLength {
                            Label("Text is too long. Maximum \(maxTextLength) characters.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Configuration")
                } footer: {
                    Text("This text will be displayed in the center of the watch screen. Press and hold the middle button on the watch to exit the app.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.blue)
                            Text("Enter your custom text above")
                                .font(.callout)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "2.circle.fill")
                                .foregroundColor(.blue)
                            Text("Tap 'Install App' to send it to your watch")
                                .font(.callout)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "3.circle.fill")
                                .foregroundColor(.blue)
                            Text("Find and launch the app from your watch's app menu")
                                .font(.callout)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "4.circle.fill")
                                .foregroundColor(.blue)
                            Text("Update the text anytime and reinstall")
                                .font(.callout)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("How It Works")
                }
                
                if watchManager.fileTransferManager.isTransferring {
                    Section("Installing") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Uploading app to watch...")
                                .font(.callout)
                            ProgressView(value: watchManager.fileTransferManager.progress)
                            Text("\(Int(watchManager.fileTransferManager.progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let message = statusMessage {
                    Section {
                        HStack {
                            Image(systemName: messageType == .success ? "checkmark.circle.fill" : messageType == .error ? "exclamationmark.circle.fill" : "info.circle.fill")
                                .foregroundColor(messageType.color)
                            Text(message)
                                .foregroundColor(messageType.color)
                        }
                    }
                }
                
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
                            Text("Install App")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isInstalling || customText.isEmpty || customText.count > maxTextLength || !watchManager.authManager.isAuthenticated)
                }
                
                if !watchManager.authManager.isAuthenticated {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Please authenticate with your watch first")
                                .font(.callout)
                        }
                    }
                }
            }
            .navigationTitle("Custom Text")
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
    
    private func installApp() {
        guard !customText.isEmpty && customText.count <= maxTextLength else {
            return
        }
        
        isInstalling = true
        statusMessage = nil
        
        logger.info("UI", "Installing custom text app with text: '\(customText)'")
        
        Task {
            do {
                // Build the custom text app
                let appData = try buildCustomTextApp(text: customText)
                
                // Save to temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("customTextApp.wapp")
                try appData.write(to: tempURL)
                
                logger.info("UI", "Built custom text app: \(appData.count) bytes")
                
                // Install via WatchManager
                try await watchManager.installApp(from: tempURL)
                
                await MainActor.run {
                    statusMessage = "Success! App installed. Check your watch's app menu."
                    messageType = .success
                    logger.info("UI", "Custom text app installed successfully")
                }
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
                
            } catch {
                await MainActor.run {
                    statusMessage = "Failed: \(error.localizedDescription)"
                    messageType = .error
                    logger.error("UI", "Custom text app installation failed: \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                isInstalling = false
            }
        }
    }
    
    private func buildCustomTextApp(text: String) throws -> Data {
        logger.info("CustomTextApp", "Building custom text app")
        
        // Create a simple layout JSON that displays the text
        let layoutJSON = """
        {
            "type": "text",
            "x": 120,
            "y": 120,
            "w": 200,
            "h": 50,
            "text": "\(text)",
            "size": 24,
            "align": "center",
            "color": 0
        }
        """
        
        // For now, we'll need a pre-compiled JerryScript snapshot
        // This is a placeholder - in a real implementation, we'd need the actual compiled code
        // For this demo, we'll create a minimal stub
        let codeSnapshot = createMinimalCodeSnapshot()
        
        let builder = WatchAppBuilder()
        let appData = try builder.buildWatchApp(
            identifier: "customTextApp",
            version: "1.0.0.0",
            displayName: "Custom Text",
            codeSnapshot: codeSnapshot,
            layoutFiles: ["text_display": layoutJSON],
            iconFiles: [:]  // No icons for now
        )
        
        return appData
    }
    
    private func createMinimalCodeSnapshot() -> Data {
        // This is a placeholder. In a real implementation, this would be a
        // pre-compiled JerryScript snapshot of the watch app code.
        // For now, we'll use a minimal stub that the watch firmware can recognize.
        
        // JerryScript snapshot header (simplified)
        // In reality, this should be a properly compiled snapshot from the JS code
        var snapshot = Data()
        
        // Jerry snapshot magic number and version
        snapshot.append(contentsOf: [0x4A, 0x52, 0x52, 0x59])  // "JRRY"
        snapshot.append(contentsOf: [0x02, 0x01, 0x00, 0x00])  // Version 2.1.0
        
        // This is a stub - a real implementation would need actual compiled JerryScript
        // For demo purposes, we'll just create a minimal valid structure
        
        logger.warning("CustomTextApp", "Using stub code snapshot - app may not function correctly")
        
        return snapshot
    }
}

#Preview {
    CustomTextAppView()
        .environmentObject(WatchManager())
}
