import SwiftUI

/// Device actions view component (sync, install app, find watch, etc.)
struct DeviceActionsView: View {
    let isAuthenticated: Bool
    let isSyncingTime: Bool
    let onSyncTime: () -> Void
    let onInstallApp: () -> Void
    let onFindWatch: () -> Void
    let onUpdateTestTrack: () -> Void
    let onSendMusicCommand: (MusicControlManager.MusicCommand) -> Void
    let onExportLogs: () -> Void
    let logSummary: String

    var body: some View {
        Section("Actions") {
            // Time Sync
            Button {
                onSyncTime()
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
            .disabled(!isAuthenticated || isSyncingTime)

            // Install App
            Button {
                onInstallApp()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 30)
                    Text("Install Watch App")
                }
            }
            .disabled(!isAuthenticated)

            // Find Watch
            Button {
                onFindWatch()
            } label: {
                HStack {
                    Image(systemName: "ipad.and.iphone")
                        .frame(width: 30)
                    Text("Find Watch")
                }
            }
            .disabled(!isAuthenticated)

            // Music Control Test
            Section("Music Control (Test)") {
                Button {
                    onUpdateTestTrack()
                } label: {
                    HStack {
                        Image(systemName: "music.note")
                            .frame(width: 30)
                        Text("Push 'Test Track' Info")
                    }
                }
                .disabled(!isAuthenticated)

                HStack {
                    Spacer()
                    Button {
                        onSendMusicCommand(.previous)
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button {
                        onSendMusicCommand(.playPause)
                    } label: {
                        Image(systemName: "playpause.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button {
                        onSendMusicCommand(.next)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.vertical, 8)
                .disabled(!isAuthenticated)
            }

            // Export Logs
            Button {
                onExportLogs()
            } label: {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .frame(width: 30)
                    VStack(alignment: .leading) {
                        Text("Export Debug Logs")
                        Text(logSummary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    List {
        DeviceActionsView(
            isAuthenticated: true,
            isSyncingTime: false,
            onSyncTime: {},
            onInstallApp: {},
            onFindWatch: {},
            onUpdateTestTrack: {},
            onSendMusicCommand: { _ in },
            onExportLogs: {},
            logSummary: "100 entries"
        )
    }
}
