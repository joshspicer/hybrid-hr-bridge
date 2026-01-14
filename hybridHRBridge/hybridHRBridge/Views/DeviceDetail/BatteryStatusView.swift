import SwiftUI

/// Battery status display view component
struct BatteryStatusView: View {
    let watch: WatchDevice?
    let isRefreshing: Bool
    let isAuthenticated: Bool
    let onRefresh: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 16) {
                // Visual Battery Indicator
                if let battery = watch?.batteryLevel {
                    BatteryVisualIndicator(level: battery)
                        .frame(height: 80)
                }
                
                // Battery Details
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

// MARK: - Battery Visual Indicator

/// Custom battery visualization
private struct BatteryVisualIndicator: View {
    let level: Int
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Battery outline
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary, lineWidth: 3)
                
                // Battery fill
                RoundedRectangle(cornerRadius: 6)
                    .fill(batteryGradient)
                    .padding(4)
                    .frame(width: geometry.size.width * CGFloat(level) / 100.0)
                
                // Battery nub (right side)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary)
                    .frame(width: 8, height: geometry.size.height * 0.4)
                    .offset(x: geometry.size.width)
                
                // Percentage text
                Text("\(level)%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(level > 50 ? .white : .primary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var batteryGradient: LinearGradient {
        let colors: [Color]
        if level <= 20 {
            colors = [.red, .orange]
        } else if level <= 50 {
            colors = [.orange, .yellow]
        } else {
            colors = [.green, .mint]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
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
