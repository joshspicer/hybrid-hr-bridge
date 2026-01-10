import SwiftUI

/// View for managing watch apps
struct AppsView: View {
    @EnvironmentObject var watchManager: WatchManager
    @State private var showingCustomTextApp = false
    @State private var showingAppInstall = false
    
    var body: some View {
        NavigationStack {
            List {
                // Authentication status
                if !watchManager.authManager.isAuthenticated {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Authentication required to manage apps")
                                .font(.callout)
                        }
                    }
                }
                
                // Custom apps section
                Section {
                    // Custom Text App
                    Button {
                        showingCustomTextApp = true
                    } label: {
                        HStack {
                            Image(systemName: "textformat")
                                .frame(width: 30)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Custom Text Display")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Display your own text on the watch")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(!watchManager.authManager.isAuthenticated)
                } header: {
                    Text("Custom Apps")
                } footer: {
                    Text("Create and configure custom watch apps that display your own content.")
                }
                
                // Install from file section
                Section {
                    Button {
                        showingAppInstall = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .frame(width: 30)
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Install from File")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Install a .wapp file")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(!watchManager.authManager.isAuthenticated)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Install custom .wapp files built with the Fossil HR SDK.")
                }
                
                // Resources section
                Section {
                    Link(destination: URL(string: "https://github.com/dakhnod/Fossil-HR-SDK")!) {
                        HStack {
                            Image(systemName: "link")
                                .frame(width: 30)
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Fossil HR SDK")
                                    .font(.body)
                                Text("Build your own watch apps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Resources")
                }
            }
            .navigationTitle("Watch Apps")
            .sheet(isPresented: $showingCustomTextApp) {
                CustomTextAppView()
                    .environmentObject(watchManager)
            }
            .sheet(isPresented: $showingAppInstall) {
                AppInstallView()
                    .environmentObject(watchManager)
            }
        }
    }
}

#Preview {
    AppsView()
        .environmentObject(WatchManager())
}
