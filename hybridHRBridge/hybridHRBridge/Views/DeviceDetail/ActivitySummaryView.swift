import SwiftUI

/// Activity summary display view component
struct ActivitySummaryView: View {
    let activityData: ActivityData?
    let isRefreshing: Bool
    let isAuthenticated: Bool
    let onRefresh: () -> Void
    let onViewDetails: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let activity = activityData {
                    HStack(spacing: 20) {
                        VStack {
                            Image(systemName: "figure.walk")
                                .foregroundColor(.blue)
                                .font(.title2)
                            Text("\(activity.totalSteps)")
                                .font(.headline)
                            Text("Steps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()
                            .frame(height: 40)

                        VStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.title2)
                            Text(activity.averageHeartRate > 0 ? "\(activity.averageHeartRate)" : "--")
                                .font(.headline)
                            Text("Avg HR")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()
                            .frame(height: 40)

                        VStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                                .font(.title2)
                            Text("\(activity.totalCalories)")
                                .font(.headline)
                            Text("Calories")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "figure.walk.circle")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        Text("No activity data")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Button {
                        onRefresh()
                    } label: {
                        HStack {
                            if isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isAuthenticated || isRefreshing)

                    Spacer()

                    if activityData != nil {
                        Button {
                            onViewDetails()
                        } label: {
                            HStack {
                                Text("View Details")
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Activity")
        }
    }
}

#Preview {
    List {
        ActivitySummaryView(
            activityData: ActivityData(samples: [], spo2Samples: [], workoutSummaries: []),
            isRefreshing: false,
            isAuthenticated: true,
            onRefresh: {},
            onViewDetails: {}
        )
    }
}
