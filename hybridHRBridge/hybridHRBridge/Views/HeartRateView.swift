import SwiftUI
import Charts

/// Heart rate monitoring view with real-time BPM display
struct HeartRateView: View {
    @EnvironmentObject var watchManager: WatchManager
    @State private var isMonitoring = false
    @State private var statusMessage: String?
    @State private var heartRateHistory: [HeartRateReading] = []
    
    private let maxHistoryPoints = 60 // Keep last 60 readings
    
    var body: some View {
        List {
            // Current Heart Rate Section
            Section {
                VStack(spacing: 16) {
                    // Large BPM Display
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(watchManager.heartRateManager.currentHeartRate)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundColor(heartRateColor)
                        Text("BPM")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Last Update Time
                    if let lastUpdate = watchManager.heartRateManager.lastUpdate {
                        Text("Updated \(timeAgoString(from: lastUpdate))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No data yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            
            // Monitoring Control Section
            Section {
                Button {
                    toggleMonitoring()
                } label: {
                    HStack {
                        Image(systemName: isMonitoring ? "stop.circle.fill" : "heart.circle.fill")
                            .font(.title2)
                            .foregroundColor(isMonitoring ? .red : .pink)
                        Text(isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                        Spacer()
                        if isMonitoring {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(!watchManager.authManager.isAuthenticated)
            } footer: {
                if !watchManager.authManager.isAuthenticated {
                    Text("Authentication required to monitor heart rate")
                } else if isMonitoring {
                    Text("Monitoring heart rate in real-time. Keep the watch screen on.")
                }
            }
            
            // Heart Rate Chart Section
            if !heartRateHistory.isEmpty {
                Section("Heart Rate History") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Chart
                        Chart(heartRateHistory) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("BPM", reading.bpm)
                            )
                            .foregroundStyle(Color.pink.gradient)
                            .interpolationMethod(.catmullRom)
                            
                            PointMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("BPM", reading.bpm)
                            )
                            .foregroundStyle(Color.pink)
                        }
                        .chartYScale(domain: 40...180)
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel()
                                AxisGridLine()
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: 15)) { _ in
                                AxisValueLabel(format: .dateTime.minute().second())
                            }
                        }
                        .frame(height: 200)
                        
                        // Stats
                        HStack(spacing: 20) {
                            StatView(
                                title: "Average",
                                value: "\(averageHeartRate)",
                                unit: "BPM"
                            )
                            
                            StatView(
                                title: "Min",
                                value: "\(minHeartRate)",
                                unit: "BPM"
                            )
                            
                            StatView(
                                title: "Max",
                                value: "\(maxHeartRate)",
                                unit: "BPM"
                            )
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 8)
                }
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
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Heart rate monitoring uses the watch's built-in sensor", systemImage: "info.circle")
                        .font(.caption)
                    Label("Keep the watch snug on your wrist for accurate readings", systemImage: "watch")
                        .font(.caption)
                    Label("Battery usage may increase during monitoring", systemImage: "battery.50")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Heart Rate")
        .onChange(of: watchManager.heartRateManager.currentHeartRate) { oldValue, newValue in
            if newValue > 0 {
                addHeartRateReading(newValue)
            }
        }
        .onChange(of: watchManager.heartRateManager.isMonitoring) { oldValue, newValue in
            isMonitoring = newValue
        }
        .onAppear {
            isMonitoring = watchManager.heartRateManager.isMonitoring
        }
    }
    
    // MARK: - Helper Views
    
    private struct StatView: View {
        let title: String
        let value: String
        let unit: String
        
        var body: some View {
            VStack(spacing: 4) {
                Text(title)
                    .foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Helper Methods
    
    private func toggleMonitoring() {
        statusMessage = nil
        
        Task {
            do {
                if isMonitoring {
                    try await watchManager.heartRateManager.stopMonitoring()
                    statusMessage = "Monitoring stopped"
                    // Clear history when stopping
                    heartRateHistory.removeAll()
                } else {
                    try await watchManager.heartRateManager.startMonitoring()
                    statusMessage = "Monitoring started"
                }
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func addHeartRateReading(_ bpm: Int) {
        let reading = HeartRateReading(
            id: UUID(),
            timestamp: Date(),
            bpm: bpm
        )
        
        heartRateHistory.append(reading)
        
        // Limit history size
        if heartRateHistory.count > maxHistoryPoints {
            heartRateHistory.removeFirst()
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        
        if seconds < 5 {
            return "just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }
    
    private var heartRateColor: Color {
        let bpm = watchManager.heartRateManager.currentHeartRate
        if bpm == 0 {
            return .secondary
        } else if bpm < 60 {
            return .blue
        } else if bpm < 100 {
            return .green
        } else if bpm < 140 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var averageHeartRate: Int {
        guard !heartRateHistory.isEmpty else { return 0 }
        let sum = heartRateHistory.reduce(0) { $0 + $1.bpm }
        return sum / heartRateHistory.count
    }
    
    private var minHeartRate: Int {
        heartRateHistory.map(\.bpm).min() ?? 0
    }
    
    private var maxHeartRate: Int {
        heartRateHistory.map(\.bpm).max() ?? 0
    }
}

// MARK: - Supporting Types

private struct HeartRateReading: Identifiable {
    let id: UUID
    let timestamp: Date
    let bpm: Int
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HeartRateView()
            .environmentObject({
                let manager = WatchManager()
                return manager
            }())
    }
}
