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
                            Text("Tap 'Build Demo App' to create a .wapp file")
                                .font(.callout)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "3.circle.fill")
                                .foregroundColor(.blue)
                            Text("The app demonstrates .wapp file structure")
                                .font(.callout)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                            Text("Note: This is a demonstration. A fully functional app requires JerryScript compilation.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("How It Works")
                } footer: {
                    Text("This feature demonstrates the custom app infrastructure. To install working apps, use 'Install from File' with pre-built .wapp files from the Fossil HR SDK or Gadgetbridge community.")
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
                            Text("Build Demo App")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isInstalling || customText.isEmpty || customText.count > maxTextLength || !watchManager.authManager.isAuthenticated)
                } footer: {
                    Text("This will create a demonstration .wapp file and attempt to install it. For fully functional apps, use pre-built .wapp files.")
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
        
        // NOTE: This is a demonstration implementation.
        // A real implementation would require:
        // 1. JerryScript 2.1.0 compiler (jerry-snapshot) to compile app.js
        // 2. Properly structured app code that responds to watch events
        // 3. Layout files that define the UI
        // 4. Icon files for the app launcher
        //
        // For now, we demonstrate the .wapp structure but cannot create
        // a fully functional app without the JerryScript toolchain.
        
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
        
        // For a real implementation, use a pre-compiled snapshot or compile with JerryScript
        // For demonstration, we'll use a minimal valid JerryScript snapshot header
        let codeSnapshot = createDemoCodeSnapshot()
        
        let builder = WatchAppBuilder()
        let appData = try builder.buildWatchApp(
            identifier: "customTextApp",
            version: "1.0.0.0",
            displayName: "Custom Text",
            codeSnapshot: codeSnapshot,
            layoutFiles: ["text_display": layoutJSON],
            iconFiles: [:]  // No icons for demonstration
        )
        
        logger.info("CustomTextApp", "Demo .wapp built: \(appData.count) bytes")
        logger.warning("CustomTextApp", "This is a demonstration .wapp - it may not work on the watch without proper JerryScript code")
        
        return appData
    }
    
    private func createDemoCodeSnapshot() -> Data {
        // This creates a minimal demonstration snapshot.
        // For a real implementation, this would be:
        // 1. A pre-compiled snapshot bundled as a resource, OR
        // 2. Compiled at build time using jerry-snapshot from the SDK
        //
        // The actual app code would need to:
        // - Handle system_state_update events
        // - Draw the layout when visible
        // - Respond to button presses
        
        var snapshot = Data()
        
        // JerryScript snapshot magic number and version
        snapshot.append(contentsOf: [0x4A, 0x52, 0x52, 0x59])  // "JRRY"
        snapshot.append(contentsOf: [0x18, 0x00, 0x00, 0x00])  // Version header
        snapshot.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // Flags
        
        // Minimal bytecode (this is a stub and won't execute properly)
        // A real snapshot would have the actual compiled JerryScript bytecode
        snapshot.append(contentsOf: [0x00, 0x40, 0x03, 0x00])  // Function table
        
        logger.debug("CustomTextApp", "Created demo snapshot: \(snapshot.count) bytes")
        
        return snapshot
    }
}

#Preview {
    CustomTextAppView()
        .environmentObject(WatchManager())
}
