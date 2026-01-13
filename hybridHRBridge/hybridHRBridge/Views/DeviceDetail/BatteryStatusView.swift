import SwiftUI

/// Battery status display view component
struct BatteryStatusView: View {
    let watch: WatchDevice?
    let isRefreshing: Bool
    let isAuthenticated: Bool
    let onRefresh: () -> Void

    var body: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: batteryIcon(for: watch?.batteryLevel))
                            .foregroundColor(batteryColor(for: watch?.batteryLevel))
                            .font(.title2)

                        if let battery = watch?.batteryLevel {
                            Text("\(battery)%")
                                .font(.title2)
                                .fontWeight(.semibold)
                        } else {
                            Text("--")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let voltage = watch?.batteryVoltageMillivolts {
                        let volts = Double(voltage) / 1000.0
                        Text(String(format: "%.3f V", volts))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!isAuthenticated || isRefreshing)
            }
        } header: {
            Text("Battery")
        }
    }

    // MARK: - Helper Methods

    private func batteryIcon(for level: Int?) -> String {
        guard let level = level else { return "battery.0" }

        switch level {
        case 0...10:
            return "battery.0"
        case 11...25:
            return "battery.25"
        case 26...50:
            return "battery.50"
        case 51...75:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    private func batteryColor(for level: Int?) -> Color {
        guard let level = level else { return .secondary }

        if level <= 20 {
            return .red
        } else if level <= 50 {
            return .orange
        } else {
            return .green
        }
    }
}

#Preview {
    var testWatch = WatchDevice(id: UUID(), name: "Test Watch")
    testWatch.batteryLevel = 75
    testWatch.batteryVoltageMillivolts = 3200

    return List {
        BatteryStatusView(
            watch: testWatch,
            isRefreshing: false,
            isAuthenticated: true,
            onRefresh: {}
        )
    }
}
