import SwiftUI

/// Alarm management view for the watch
struct AlarmListView: View {
    @EnvironmentObject var watchManager: WatchManager
    @State private var showingAddAlarm = false
    @State private var editingAlarm: AlarmManager.WatchAlarm?
    @State private var statusMessage: String?
    @State private var isSyncing = false
    
    var body: some View {
        List {
            // Alarms Section
            Section {
                if watchManager.alarmManager.alarms.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "alarm")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No alarms set")
                            .foregroundColor(.secondary)
                        Button("Add First Alarm") {
                            showingAddAlarm = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(watchManager.alarmManager.alarms) { alarm in
                        AlarmRow(alarm: alarm)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingAlarm = alarm
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteAlarm(alarm)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                if !watchManager.alarmManager.alarms.isEmpty {
                    Text("Alarms (\(watchManager.alarmManager.alarms.count))")
                }
            }
            
            // Quick Timer Section
            Section {
                Button {
                    setQuickTimer()
                } label: {
                    HStack {
                        Image(systemName: "timer")
                            .frame(width: 30)
                        Text("Set Quick 5-Minute Timer")
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated || isSyncing)
            } header: {
                Text("Quick Actions")
            } footer: {
                Text("Sets a one-time alarm 5 minutes from now")
            }
            
            // Status Message
            if let message = statusMessage {
                Section {
                    Text(message)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            // Info Section
            if !watchManager.authManager.isAuthenticated {
                Section {
                    Text("Authentication required to manage alarms")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Alarms")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddAlarm = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!watchManager.authManager.isAuthenticated || isSyncing)
            }
            
            if isSyncing {
                ToolbarItem(placement: .status) {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .sheet(isPresented: $showingAddAlarm) {
            NavigationStack {
                AlarmEditView(alarm: nil, onSave: addAlarm)
            }
        }
        .sheet(item: $editingAlarm) { alarm in
            NavigationStack {
                AlarmEditView(alarm: alarm, onSave: updateAlarm)
            }
        }
    }
    
    // MARK: - Actions
    
    private func addAlarm(_ alarm: AlarmManager.WatchAlarm) {
        statusMessage = nil
        isSyncing = true
        
        watchManager.alarmManager.addAlarm(alarm)
        
        Task {
            do {
                try await watchManager.alarmManager.syncAlarms()
                await MainActor.run {
                    statusMessage = "Alarm added successfully"
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to sync: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func updateAlarm(_ alarm: AlarmManager.WatchAlarm) {
        statusMessage = nil
        isSyncing = true
        
        watchManager.alarmManager.updateAlarm(alarm)
        
        Task {
            do {
                try await watchManager.alarmManager.syncAlarms()
                await MainActor.run {
                    statusMessage = "Alarm updated successfully"
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to sync: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func deleteAlarm(_ alarm: AlarmManager.WatchAlarm) {
        statusMessage = nil
        isSyncing = true
        
        watchManager.alarmManager.removeAlarm(alarm)
        
        Task {
            do {
                try await watchManager.alarmManager.syncAlarms()
                await MainActor.run {
                    statusMessage = "Alarm deleted"
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to sync: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func setQuickTimer() {
        statusMessage = nil
        isSyncing = true
        
        let now = Date()
        let futureTime = now.addingTimeInterval(5 * 60) // 5 minutes
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: futureTime)
        let minute = calendar.component(.minute, from: futureTime)
        
        Task {
            do {
                try await watchManager.alarmManager.setQuickAlarm(hour: hour, minute: minute, title: "Timer")
                await MainActor.run {
                    statusMessage = "Timer set for \(String(format: "%02d:%02d", hour, minute))"
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to set timer: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
}

// MARK: - Alarm Row

private struct AlarmRow: View {
    let alarm: AlarmManager.WatchAlarm
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Time
                Text(timeString)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(alarm.enabled ? .primary : .secondary)
                
                // Title & Repeat
                HStack(spacing: 8) {
                    Text(alarm.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if alarm.repeatDays != .none {
                        Text(repeatString)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            // Enable/Disable indicator
            Circle()
                .fill(alarm.enabled ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
        }
        .padding(.vertical, 4)
    }
    
    private var timeString: String {
        String(format: "%02d:%02d", alarm.hour, alarm.minute)
    }
    
    private var repeatString: String {
        if alarm.repeatDays == .everyday {
            return "Every day"
        } else if alarm.repeatDays == .weekdays {
            return "Weekdays"
        } else if alarm.repeatDays == .weekends {
            return "Weekends"
        } else {
            var days: [String] = []
            if alarm.repeatDays.contains(.sunday) { days.append("Sun") }
            if alarm.repeatDays.contains(.monday) { days.append("Mon") }
            if alarm.repeatDays.contains(.tuesday) { days.append("Tue") }
            if alarm.repeatDays.contains(.wednesday) { days.append("Wed") }
            if alarm.repeatDays.contains(.thursday) { days.append("Thu") }
            if alarm.repeatDays.contains(.friday) { days.append("Fri") }
            if alarm.repeatDays.contains(.saturday) { days.append("Sat") }
            return days.joined(separator: ", ")
        }
    }
}

// MARK: - Alarm Edit View

private struct AlarmEditView: View {
    let alarm: AlarmManager.WatchAlarm?
    let onSave: (AlarmManager.WatchAlarm) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var hour: Int
    @State private var minute: Int
    @State private var enabled: Bool
    @State private var repeatDays: AlarmManager.RepeatDays
    @State private var title: String
    @State private var message: String
    
    init(alarm: AlarmManager.WatchAlarm?, onSave: @escaping (AlarmManager.WatchAlarm) -> Void) {
        self.alarm = alarm
        self.onSave = onSave
        
        // Initialize state
        _hour = State(initialValue: alarm?.hour ?? Calendar.current.component(.hour, from: Date()))
        _minute = State(initialValue: alarm?.minute ?? 0)
        _enabled = State(initialValue: alarm?.enabled ?? true)
        _repeatDays = State(initialValue: alarm?.repeatDays ?? .none)
        _title = State(initialValue: alarm?.title ?? "Alarm")
        _message = State(initialValue: alarm?.message ?? "")
    }
    
    var body: some View {
        Form {
            // Time Picker
            Section {
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { timeFromComponents },
                        set: { updateTimeComponents($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
            }
            
            // Alarm Details
            Section {
                TextField("Title", text: $title)
                Toggle("Enabled", isOn: $enabled)
            }
            
            // Repeat Days
            Section("Repeat") {
                Button {
                    repeatDays = .none
                } label: {
                    HStack {
                        Text("Never")
                        Spacer()
                        if repeatDays == .none {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
                
                Button {
                    repeatDays = .everyday
                } label: {
                    HStack {
                        Text("Every Day")
                        Spacer()
                        if repeatDays == .everyday {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
                
                Button {
                    repeatDays = .weekdays
                } label: {
                    HStack {
                        Text("Weekdays")
                        Spacer()
                        if repeatDays == .weekdays {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
                
                Toggle("Sunday", isOn: Binding(
                    get: { repeatDays.contains(.sunday) },
                    set: { if $0 { repeatDays.insert(.sunday) } else { repeatDays.remove(.sunday) } }
                ))
                Toggle("Monday", isOn: Binding(
                    get: { repeatDays.contains(.monday) },
                    set: { if $0 { repeatDays.insert(.monday) } else { repeatDays.remove(.monday) } }
                ))
                Toggle("Tuesday", isOn: Binding(
                    get: { repeatDays.contains(.tuesday) },
                    set: { if $0 { repeatDays.insert(.tuesday) } else { repeatDays.remove(.tuesday) } }
                ))
                Toggle("Wednesday", isOn: Binding(
                    get: { repeatDays.contains(.wednesday) },
                    set: { if $0 { repeatDays.insert(.wednesday) } else { repeatDays.remove(.wednesday) } }
                ))
                Toggle("Thursday", isOn: Binding(
                    get: { repeatDays.contains(.thursday) },
                    set: { if $0 { repeatDays.insert(.thursday) } else { repeatDays.remove(.thursday) } }
                ))
                Toggle("Friday", isOn: Binding(
                    get: { repeatDays.contains(.friday) },
                    set: { if $0 { repeatDays.insert(.friday) } else { repeatDays.remove(.friday) } }
                ))
                Toggle("Saturday", isOn: Binding(
                    get: { repeatDays.contains(.saturday) },
                    set: { if $0 { repeatDays.insert(.saturday) } else { repeatDays.remove(.saturday) } }
                ))
            }
        }
        .navigationTitle(alarm == nil ? "New Alarm" : "Edit Alarm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAlarm()
                }
            }
        }
    }
    
    private var timeFromComponents: Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
    
    private func updateTimeComponents(_ date: Date) {
        let calendar = Calendar.current
        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }
    
    private func saveAlarm() {
        let newAlarm = AlarmManager.WatchAlarm(
            id: alarm?.id ?? UUID(),
            hour: hour,
            minute: minute,
            enabled: enabled,
            repeatDays: repeatDays,
            title: title,
            message: message
        )
        
        onSave(newAlarm)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AlarmListView()
            .environmentObject({
                let manager = WatchManager()
                return manager
            }())
    }
}
