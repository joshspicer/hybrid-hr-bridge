import SwiftUI
import UniformTypeIdentifiers

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
