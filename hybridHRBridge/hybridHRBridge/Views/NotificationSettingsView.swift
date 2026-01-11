import SwiftUI
import UserNotifications

/// View for managing iOS notification integration with the watch
struct NotificationSettingsView: View {
    @EnvironmentObject var watchManager: WatchManager
    @StateObject private var notificationService: NotificationService
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    init(notificationService: NotificationService) {
        _notificationService = StateObject(wrappedValue: notificationService)
    }
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("iOS Notification Integration")
                        .font(.headline)
                    Text("Allow this app to intercept iOS notifications and forward them to your watch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Permission Status") {
                HStack {
                    Text("iOS Notifications")
                    Spacer()
                    permissionStatusBadge
                }
                
                if notificationService.notificationPermissionStatus != .authorized {
                    Button {
                        Task {
                            isLoading = true
                            await watchManager.requestNotificationPermissions()
                            await watchManager.checkNotificationPermissionStatus()
                            isLoading = false
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text("Request Permission")
                        }
                    }
                    .disabled(isLoading)
                }
                
                HStack {
                    Text("ANCS (System)")
                    Spacer()
                    ancsStatusBadge
                }
                .contextMenu {
                    Button("Open Bluetooth Settings") {
                        if let url = URL(string: "App-Prefs:root=Bluetooth") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            
            Section("Notification Statistics") {
                HStack {
                    Text("Notifications Received")
                    Spacer()
                    Text("\(notificationService.notificationCount)")
                        .foregroundColor(.secondary)
                }
                
                if let lastNotification = notificationService.lastNotification {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Notification")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lastNotification.appIdentifier)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(lastNotification.displayText)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
            
            Section("Actions") {
                Button {
                    Task {
                        isLoading = true
                        await watchManager.sendTestNotification()
                        isLoading = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Send Test Notification")
                    }
                }
                .disabled(isLoading || watchManager.connectionStatus != .authenticated)
                
                Button {
                    Task {
                        isLoading = true
                        await watchManager.configureWatchNotifications()
                        isLoading = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Configure Watch")
                    }
                }
                .disabled(isLoading || watchManager.connectionStatus != .authenticated)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ Important Notes")
                        .font(.headline)
                    
                    Text("1. Request iOS notification permissions above")
                        .font(.caption)
                    
                    Text("2. Enable 'Share System Notifications' in iOS Settings > Bluetooth > [Watch] > (i)")
                        .font(.caption)
                    
                    Text("3. Watch must be connected and authenticated")
                        .font(.caption)
                    
                    Text("4. Notifications require a watchface with notification widget (see research docs)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Section("Research Status") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phase 1: iOS Notification Access")
                        .font(.caption)
                    Text("✅ Implemented - Request permissions and intercept notifications")
                        .font(.caption2)
                        .foregroundColor(.green)
                    
                    Text("Phase 2: Protocol Implementation")
                        .font(.caption)
                        .padding(.top, 4)
                    Text("🚧 In Progress - Icon encoding and filter configuration")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    Text("Phase 3: File Transfer Integration")
                        .font(.caption)
                        .padding(.top, 4)
                    Text("⏳ Pending - Upload icons/filters and send notifications")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await watchManager.checkNotificationPermissionStatus()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private var permissionStatusBadge: some View {
        Group {
            switch notificationService.notificationPermissionStatus {
            case .notDetermined:
                Label("Not Requested", systemImage: "questionmark.circle")
                    .foregroundColor(.orange)
            case .denied:
                Label("Denied", systemImage: "xmark.circle")
                    .foregroundColor(.red)
            case .authorized:
                Label("Authorized", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            case .provisional:
                Label("Provisional", systemImage: "checkmark.circle.trianglebadge.exclamationmark")
                    .foregroundColor(.yellow)
            case .ephemeral:
                Label("Ephemeral", systemImage: "clock.badge.checkmark")
                    .foregroundColor(.blue)
            @unknown default:
                Label("Unknown", systemImage: "questionmark.circle")
                    .foregroundColor(.gray)
            }
        }
        .font(.caption)
    }
    
    private var ancsStatusBadge: some View {
        Group {
            if watchManager.ancsAuthorized {
                Label("Authorized", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            } else {
                Label("Not Authorized", systemImage: "xmark.circle")
                    .foregroundColor(.orange)
            }
        }
        .font(.caption)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(notificationService: NotificationService())
            .environmentObject(WatchManager())
    }
}
