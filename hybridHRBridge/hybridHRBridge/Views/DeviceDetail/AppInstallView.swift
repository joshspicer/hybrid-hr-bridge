import SwiftUI
import UniformTypeIdentifiers

/// View for installing watch apps (.wapp files)
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
