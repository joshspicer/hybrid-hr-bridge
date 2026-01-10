import Foundation

/// Represents a single activity sample from the watch (1 minute interval)
/// Source: ActivityEntry.java
/// https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/parser/ActivityEntry.java
struct ActivityEntry: Identifiable, Equatable, Codable {
    let id: Int
    
    /// Unix timestamp for this sample
    let timestamp: Int
    
    /// Number of steps in this minute
    let stepCount: Int
    
    /// Heart rate in BPM (0 if not measured)
    let heartRate: Int
    
    /// Heart rate quality indicator (0-7, higher is better)
    let heartRateQuality: Int
    
    /// Heart rate variability
    let variability: Int
    
    /// Maximum heart rate variability
    let maxVariability: Int
    
    /// Calories burned in this minute
    let calories: Int
    
    /// Whether this was an active minute (exercise)
    let isActive: Bool
    
    /// Watch wearing state
    let wearingState: WearingState
    
    /// Date representation of the timestamp
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    /// Watch wearing state enumeration
    /// Source: ActivityEntry.java WEARING_STATE enum
    enum WearingState: UInt8, Codable, CustomStringConvertible {
        case wearing = 0
        case notWearing = 1
        case unknown = 2
        
        var description: String {
            switch self {
            case .wearing: return "Wearing"
            case .notWearing: return "Not Wearing"
            case .unknown: return "Unknown"
            }
        }
        
        static func from(value: UInt8) -> WearingState {
            WearingState(rawValue: value) ?? .unknown
        }
    }
}

// MARK: - CustomStringConvertible

extension ActivityEntry: CustomStringConvertible {
    var description: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "[\(formatter.string(from: date))] Steps: \(stepCount), HR: \(heartRate), Cal: \(calories), Active: \(isActive)"
    }
}

// MARK: - SpO2 Sample

/// Represents a blood oxygen (SpO2) measurement sample
/// Source: HybridHRSpo2Sample from Gadgetbridge
struct SpO2Sample: Identifiable, Equatable, Codable {
    let id: UUID
    
    /// Unix timestamp in milliseconds
    let timestamp: Int64
    
    /// SpO2 percentage (typically 80-100%)
    let spo2: Int
    
    /// Date representation
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    }
    
    init(timestamp: Int64, spo2: Int) {
        self.id = UUID()
        self.timestamp = timestamp
        self.spo2 = spo2
    }
}

// MARK: - Workout Summary

/// Represents a workout session summary
/// Source: BaseActivitySummary from Gadgetbridge
struct WorkoutSummary: Identifiable, Equatable, Codable {
    let id: UUID
    
    /// Workout type
    let activityKind: ActivityKind
    
    /// Start time of the workout
    let startTime: Date
    
    /// End time of the workout
    let endTime: Date
    
    /// Raw workout data for detailed parsing
    let rawData: Data
    
    /// Duration of the workout in seconds
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    /// Workout type enumeration
    /// Source: ActivityKind.java workout types
    enum ActivityKind: UInt8, Codable, CustomStringConvertible {
        case activity = 0
        case running = 1
        case cycling = 2
        case treadmill = 3
        case crossTrainer = 4
        case weightlifting = 5
        case training = 6
        case walking = 8
        case rowingMachine = 9
        case hiking = 12
        case spinning = 13
        case unknown = 255
        
        var description: String {
            switch self {
            case .activity: return "Activity"
            case .running: return "Running"
            case .cycling: return "Cycling"
            case .treadmill: return "Treadmill"
            case .crossTrainer: return "Cross Trainer"
            case .weightlifting: return "Weightlifting"
            case .training: return "Training"
            case .walking: return "Walking"
            case .rowingMachine: return "Rowing Machine"
            case .hiking: return "Hiking"
            case .spinning: return "Spinning"
            case .unknown: return "Unknown"
            }
        }
        
        static func from(value: UInt8) -> ActivityKind {
            ActivityKind(rawValue: value) ?? .unknown
        }
    }
    
    init(activityKind: ActivityKind, startTime: Date, endTime: Date, rawData: Data = Data()) {
        self.id = UUID()
        self.activityKind = activityKind
        self.startTime = startTime
        self.endTime = endTime
        self.rawData = rawData
    }
}

// MARK: - Activity Data Container

/// Container for all parsed activity data from the watch
struct ActivityData: Equatable {
    /// Activity samples (1 per minute)
    let samples: [ActivityEntry]
    
    /// SpO2 measurements (if supported by device)
    let spo2Samples: [SpO2Sample]
    
    /// Workout summaries
    let workoutSummaries: [WorkoutSummary]
    
    /// Total steps across all samples
    var totalSteps: Int {
        samples.reduce(0) { $0 + $1.stepCount }
    }
    
    /// Average heart rate (excluding zero values)
    var averageHeartRate: Int {
        let validSamples = samples.filter { $0.heartRate > 0 }
        guard !validSamples.isEmpty else { return 0 }
        return validSamples.reduce(0) { $0 + $1.heartRate } / validSamples.count
    }
    
    /// Total calories burned
    var totalCalories: Int {
        samples.reduce(0) { $0 + $1.calories }
    }
    
    /// Time range covered by the data
    var dateRange: ClosedRange<Date>? {
        guard let first = samples.first, let last = samples.last else { return nil }
        return first.date...last.date
    }
    
    /// Empty activity data
    static let empty = ActivityData(samples: [], spo2Samples: [], workoutSummaries: [])
}
