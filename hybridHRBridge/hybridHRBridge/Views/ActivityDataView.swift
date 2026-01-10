import SwiftUI
import Charts

/// View for displaying activity data fetched from the watch
struct ActivityDataView: View {
    @EnvironmentObject private var watchManager: WatchManager
    
    @State private var activityData: ActivityData?
    @State private var isFetching = false
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    
    private let logger = LogManager.shared
    
    var body: some View {
        NavigationStack {
            VStack {
                if isFetching {
                    fetchingView
                } else if let data = activityData {
                    activityContentView(data: data)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Activity Data")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await fetchData() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isFetching || !watchManager.authManager.isAuthenticated)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var fetchingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Fetching activity data...")
                .font(.headline)
            
            if watchManager.activityDataManager.progress > 0 {
                ProgressView(value: watchManager.activityDataManager.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                
                Text("\(Int(watchManager.activityDataManager.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Activity Data")
                .font(.headline)
            
            Text("Tap the refresh button to fetch activity data from your watch.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if !watchManager.authManager.isAuthenticated {
                Text("⚠️ Connect and authenticate with your watch first")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            Button {
                Task { await fetchData() }
            } label: {
                Label("Fetch Activity Data", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!watchManager.authManager.isAuthenticated)
        }
        .padding()
    }
    
    private func activityContentView(data: ActivityData) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary cards
                summaryCardsView(data: data)
                
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    Text("Steps").tag(0)
                    Text("Heart Rate").tag(1)
                    Text("Details").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Content based on selected tab
                switch selectedTab {
                case 0:
                    stepsChartView(data: data)
                case 1:
                    heartRateChartView(data: data)
                default:
                    detailsListView(data: data)
                }
                
                // Workout summaries
                if !data.workoutSummaries.isEmpty {
                    workoutSummariesView(workouts: data.workoutSummaries)
                }
                
                // SpO2 if available
                if !data.spo2Samples.isEmpty {
                    spo2View(samples: data.spo2Samples)
                }
            }
            .padding()
        }
    }
    
    private func summaryCardsView(data: ActivityData) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            SummaryCard(
                title: "Steps",
                value: "\(data.totalSteps)",
                icon: "figure.walk",
                color: .blue
            )
            
            SummaryCard(
                title: "Avg HR",
                value: data.averageHeartRate > 0 ? "\(data.averageHeartRate) bpm" : "--",
                icon: "heart.fill",
                color: .red
            )
            
            SummaryCard(
                title: "Calories",
                value: "\(data.totalCalories)",
                icon: "flame.fill",
                color: .orange
            )
            
            SummaryCard(
                title: "Samples",
                value: "\(data.samples.count)",
                icon: "chart.bar.fill",
                color: .purple
            )
        }
    }
    
    @ViewBuilder
    private func stepsChartView(data: ActivityData) -> some View {
        if #available(iOS 16.0, *) {
            VStack(alignment: .leading) {
                Text("Steps Over Time")
                    .font(.headline)
                
                Chart(data.samples.prefix(60)) { sample in
                    BarMark(
                        x: .value("Time", sample.date),
                        y: .value("Steps", sample.stepCount)
                    )
                    .foregroundStyle(.blue.gradient)
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        } else {
            Text("Charts require iOS 16+")
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func heartRateChartView(data: ActivityData) -> some View {
        if #available(iOS 16.0, *) {
            let validSamples = data.samples.filter { $0.heartRate > 0 }.prefix(60)
            
            VStack(alignment: .leading) {
                Text("Heart Rate Over Time")
                    .font(.headline)
                
                if validSamples.isEmpty {
                    Text("No heart rate data available")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                } else {
                    Chart(Array(validSamples)) { sample in
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("BPM", sample.heartRate)
                        )
                        .foregroundStyle(.red.gradient)
                        
                        PointMark(
                            x: .value("Time", sample.date),
                            y: .value("BPM", sample.heartRate)
                        )
                        .foregroundStyle(.red)
                    }
                    .frame(height: 200)
                    .chartYScale(domain: 40...180)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        } else {
            Text("Charts require iOS 16+")
                .foregroundColor(.secondary)
        }
    }
    
    private func detailsListView(data: ActivityData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity Samples")
                .font(.headline)
            
            if let range = data.dateRange {
                Text("From \(range.lowerBound, style: .date) to \(range.upperBound, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ForEach(data.samples.prefix(20)) { sample in
                ActivitySampleRow(sample: sample)
            }
            
            if data.samples.count > 20 {
                Text("... and \(data.samples.count - 20) more samples")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func workoutSummariesView(workouts: [WorkoutSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workouts")
                .font(.headline)
            
            ForEach(workouts) { workout in
                HStack {
                    Image(systemName: workoutIcon(for: workout.activityKind))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading) {
                        Text(workout.activityKind.description)
                            .font(.subheadline)
                        Text(workout.startTime, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(formatDuration(workout.duration))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func spo2View(samples: [SpO2Sample]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blood Oxygen (SpO2)")
                .font(.headline)
            
            ForEach(samples) { sample in
                HStack {
                    Image(systemName: "lungs.fill")
                        .foregroundColor(.cyan)
                    
                    Text("\(sample.spo2)%")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text(sample.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    private func fetchData() async {
        logger.info("UI", "User initiated activity data fetch")
        isFetching = true
        errorMessage = nil
        
        do {
            activityData = try await watchManager.fetchActivityData()
            logger.info("UI", "Activity data fetch completed successfully")
        } catch {
            logger.error("UI", "Activity data fetch failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        
        isFetching = false
    }
    
    private func workoutIcon(for kind: WorkoutSummary.ActivityKind) -> String {
        switch kind {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .treadmill: return "figure.run"
        case .crossTrainer, .training: return "dumbbell.fill"
        case .weightlifting: return "scalemass.fill"
        case .rowingMachine: return "oar.2.crossed"
        case .spinning: return "bicycle"
        default: return "figure.mixed.cardio"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m \(seconds)s"
    }
}

// MARK: - Supporting Views

private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

private struct ActivitySampleRow: View {
    let sample: ActivityEntry
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sample.date, style: .time)
                    .font(.subheadline)
                Text(sample.wearingState.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Label("\(sample.stepCount)", systemImage: "figure.walk")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                if sample.heartRate > 0 {
                    Label("\(sample.heartRate)", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if sample.calories > 0 {
                    Label("\(sample.calories)", systemImage: "flame.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                if sample.isActive {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ActivityDataView()
        .environmentObject(WatchManager())
}
