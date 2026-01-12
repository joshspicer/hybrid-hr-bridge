import Foundation

/// Parser for Fossil Hybrid HR activity file format
/// Converts raw activity file bytes into structured ActivityEntry objects
///
/// Source: ActivityFileParser.java
/// https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/parser/ActivityFileParser.java
final class ActivityFileParser {
    
    // MARK: - Private State
    
    /// Current heart rate quality (0-7)
    private var heartRateQuality: Int = 0
    
    /// Current wearing state
    private var wearingState: ActivityEntry.WearingState = .wearing
    
    /// Current timestamp (Unix seconds)
    private var currentTimestamp: Int = 0
    
    /// Current sample being built
    private var currentSample: MutableActivityEntry?
    
    /// Sample ID counter
    private var currentId: Int = 1
    
    /// Parsed activity samples
    private var samples: [ActivityEntry] = []
    
    /// Parsed SpO2 samples
    private var spo2Samples: [SpO2Sample] = []
    
    /// Parsed workout summaries
    private var workoutSummaries: [WorkoutSummary] = []
    
    // MARK: - Public API
    
    /// Parse the activity file data
    /// - Parameter data: Raw activity file bytes
    /// - Returns: Parsed activity data container
    func parseFile(_ data: Data) throws -> ActivityData {
        print("[ActivityParser] Starting to parse activity file (\(data.count) bytes)")
        
        guard data.count >= 52 else {
            print("[ActivityParser] Activity file too small: \(data.count) bytes")
            throw ActivityParserError.fileTooSmall
        }
        
        // Reset state
        resetState()
        
        // Parse header
        let buffer = ByteBufferReader(data: data)
        
        // Read file version at offset 2
        buffer.position = 2
        guard let version = buffer.getUInt16() else {
            throw ActivityParserError.fileTooSmall
        }
        print("[ActivityParser] Activity file version: \(version)")
        
        // Version 22 is the expected format (from Gadgetbridge)
        if version != 22 {
            print("[ActivityParser] Warning: Unexpected file version \(version) (expected 22), attempting to parse anyway")
        }
        
        // Read initial timestamp at offset 8
        buffer.position = 8
        guard let timestamp = buffer.getUInt32() else {
            throw ActivityParserError.fileTooSmall
        }
        currentTimestamp = Int(timestamp)
        print("[ActivityParser] Initial timestamp: \(currentTimestamp) (\(Date(timeIntervalSince1970: TimeInterval(currentTimestamp))))")
        
        // Read time offset minutes at offset 12
        let timeOffsetMinutes = buffer.getInt16() ?? 0
        print("[ActivityParser] Time offset: \(timeOffsetMinutes) minutes")
        
        // Read file ID at offset 16
        let fileId = buffer.getUInt16() ?? 0
        print("[ActivityParser] File ID: \(fileId)")
        
        // Skip to data at offset 52 (32 bytes after initial 20 byte header)
        buffer.position = 52
        finishCurrentPacket()
        
        // Parse packets
        while buffer.position < buffer.count - 4 {
            guard let next = buffer.getByte() else { break }
            
            parsePacket(next, buffer: buffer)
        }
        
        let result = ActivityData(
            samples: samples,
            spo2Samples: spo2Samples,
            workoutSummaries: workoutSummaries
        )
        
        print("[ActivityParser] Parsed \(samples.count) activity samples, \(spo2Samples.count) SpO2 samples, \(workoutSummaries.count) workouts")
        print("[ActivityParser] Total steps: \(result.totalSteps), Avg HR: \(result.averageHeartRate), Total calories: \(result.totalCalories)")
        
        return result
    }
    
    // MARK: - Packet Parsing
    
    private func parsePacket(_ byte: UInt8, buffer: ByteBufferReader) {
        switch byte {
        case 0xCE:
            parseCEPacket(buffer: buffer)
            
        case 0xC2:
            // Unknown packet, skip 3 bytes
            // Source: ActivityFileParser.java#L131-L132
            buffer.skip(3)
            
        case 0xE2:
            // Unknown packet, skip 9 bytes
            // Source: ActivityFileParser.java#L134-L140
            buffer.skip(9)
            if let nextByte = buffer.peekByte(), !isValidFlag(nextByte) {
                buffer.skip(6)
            }
            
        case 0xE0:
            // Workout summary
            parseWorkoutSummary(buffer: buffer)
            
        case 0xDD:
            // Unknown packet, skip 20 bytes
            // Source: ActivityFileParser.java#L193
            buffer.skip(20)
            
        case 0xD6:
            // SpO2 sample (standalone)
            // Source: ActivityFileParser.java#L195-L199
            _ = buffer.getByte() // Unknown statistic byte
            if let spo2Value = buffer.getByte() {
                let sample = SpO2Sample(timestamp: Int64(currentTimestamp) * 1000, spo2: Int(spo2Value))
                spo2Samples.append(sample)
            }
            
        case 0xCB, 0xCC, 0xCF:
            // Rare packets, skip 1 byte
            // Source: ActivityFileParser.java#L201-L204
            buffer.skip(1)
            
        default:
            // Unknown packet type - skip silently
            break
        }
    }
    
    /// Parse 0xCE packet - main activity data packet
    /// Source: ActivityFileParser.java#L67-L128
    private func parseCEPacket(buffer: ByteBufferReader) {
        guard let wearByte = buffer.getByte(),
              let f1 = buffer.getByte(),
              let f2 = buffer.getByte() else { return }
        
        parseWearByte(wearByte)
        
        if f1 == 0xE2 && f2 == 0x04 {
            // Timestamp update
            guard let timestamp = buffer.getUInt32() else { return }
            _ = buffer.getUInt16() // duration
            _ = buffer.getUInt16() // minutes offset
            currentTimestamp = Int(timestamp)
            
        } else if f1 == 0xD3 {
            // Workout-related packet
            parseWorkoutRelatedPacket(f2: f2, buffer: buffer)
            
        } else if f1 == 0xCF || f1 == 0xDF {
            // Not sure what to do with this
            return
            
        } else if f1 == 0xD6 {
            // SpO2 within CE packet
            if let spo2Value = buffer.getByte() {
                let sample = SpO2Sample(timestamp: Int64(currentTimestamp) * 1000, spo2: Int(spo2Value))
                spo2Samples.append(sample)
            }
            buffer.skip(3) // Likely sample statistics
            
        } else if f1 == 0xFE && f2 == 0xFE {
            // Edge case handling
            if buffer.peekByte() == 0xFE {
                buffer.skip(1)
            }
            
        } else if let checkByte = buffer.peekByteAt(offset: 2), isValidFlag(checkByte) {
            // Activity data with variability
            parseVariabilityBytes(lower: f1, higher: f2)
            
            if let heartRate = buffer.getByte(),
               let caloriesByte = buffer.getByte() {
                let isActive = (caloriesByte & 0x40) == 0x40
                let calories = Int(caloriesByte & 0x3F)
                
                currentSample?.heartRate = Int(heartRate)
                currentSample?.calories = calories
                currentSample?.isActive = isActive
                finishCurrentPacket()
            }
            return
        }
        
        // Parse remaining activity data
        parseRemainingActivityData(buffer: buffer)
    }
    
    /// Parse workout-related 0xD3 packet
    /// Source: ActivityFileParser.java#L80-L102
    private func parseWorkoutRelatedPacket(f2: UInt8, buffer: ByteBufferReader) {
        buffer.skip(2) // Info bytes
        
        guard let v1 = buffer.getByte() else { return }
        let v2 = buffer.peekByte() ?? 0
        
        if v1 == 0xDF {
            buffer.skip(1)
            if buffer.peekByteAt(offset: -3) == 0x08 {
                buffer.skip(11)
            } else if let checkByte = buffer.peekByteAt(offset: 4), !isValidFlag(checkByte) {
                buffer.skip(3)
            }
        } else if v1 == 0xE2 && v2 == 0x04 {
            buffer.skip(13)
            if let checkByte = buffer.peekByte(), !isValidFlag(checkByte) {
                buffer.skip(3)
            }
        } else if let checkByte = buffer.peekByteAt(offset: 4), !isValidFlag(checkByte) {
            buffer.skip(1)
        }
    }
    
    /// Parse remaining activity data after header processing
    private func parseRemainingActivityData(buffer: ByteBufferReader) {
        guard buffer.position < buffer.count - 4 else { return }
        
        guard let lower = buffer.getByte(),
              let higher = buffer.getByte(),
              let heartRate = buffer.getByte(),
              let caloriesByte = buffer.getByte() else { return }
        
        parseVariabilityBytes(lower: lower, higher: higher)
        
        let isActive = (caloriesByte & 0x40) == 0x40
        let calories = Int(caloriesByte & 0x3F)
        
        currentSample?.heartRate = Int(heartRate)
        currentSample?.calories = calories
        currentSample?.isActive = isActive
        finishCurrentPacket()
    }
    
    /// Parse workout summary (0xE0 packet)
    /// Source: ActivityFileParser.java#L143-L190
    private func parseWorkoutSummary(buffer: ByteBufferReader) {
        var activityKind: WorkoutSummary.ActivityKind = .activity
        var duration: Int = 0
        var rawData = Data()
        
        // Parse 14 attributes
        for _ in 0..<14 {
            guard let attributeId = buffer.getByte(),
                  let size = buffer.getByte() else { break }
            
            rawData.append(attributeId)
            rawData.append(size)
            
            guard let attributeData = buffer.getBytes(count: Int(size)) else { break }
            rawData.append(contentsOf: attributeData)
            
            // Attribute 2 is duration in seconds
            if attributeId == 2 && attributeData.count >= 4 {
                duration = Int(ByteBufferReader(data: Data(attributeData)).getUInt32() ?? 0)
            }
            
            // Attribute 9 is workout type
            if attributeId == 9 && !attributeData.isEmpty {
                activityKind = mapWorkoutType(attributeData[0])
            }
        }
        
        let endTime = Date(timeIntervalSince1970: TimeInterval(currentTimestamp))
        let startTime = Date(timeIntervalSince1970: TimeInterval(currentTimestamp - duration))
        
        let summary = WorkoutSummary(
            activityKind: activityKind,
            startTime: startTime,
            endTime: endTime,
            rawData: rawData
        )
        workoutSummaries.append(summary)
        
        print("[ActivityParser] Workout summary: \(activityKind), duration: \(duration)s")
    }
    
    /// Map workout type byte to ActivityKind
    /// Source: ActivityFileParser.java#L168-L181
    private func mapWorkoutType(_ byte: UInt8) -> WorkoutSummary.ActivityKind {
        switch byte {
        case 0x01: return .running
        case 0x02: return .cycling
        case 0x03: return .treadmill
        case 0x04: return .crossTrainer
        case 0x05: return .weightlifting
        case 0x06: return .training
        case 0x08: return .walking
        case 0x09: return .rowingMachine
        case 0x0c: return .hiking
        case 0x0d: return .spinning
        default: return .activity
        }
    }
    
    // MARK: - State Parsing Helpers
    
    /// Parse wearing state and heart rate quality from wear byte
    /// Source: ActivityFileParser.java#L225-L232
    private func parseWearByte(_ byte: UInt8) {
        let wearBits = (byte & 0b00011000) >> 3
        switch wearBits {
        case 0: wearingState = .notWearing
        case 1: wearingState = .wearing
        default: wearingState = .unknown
        }
        
        heartRateQuality = Int((byte & 0b11100000) >> 5)
    }
    
    /// Parse variability bytes to extract step count and heart rate variability
    /// Source: ActivityFileParser.java#L207-L223
    private func parseVariabilityBytes(lower: UInt8, higher: UInt8) {
        if (lower & 0b0000001) == 0b0000001 {
            currentSample?.maxVariability = Int(higher & 0b00000011) * 25 + 1
            // Shift right by 1 because the first bit is a flag
            currentSample?.stepCount = Int((lower & 0b1110) >> 1)
            
            if (lower & 0b10000000) == 0b10000000 {
                let factor = Int((lower >> 4) & 0b111)
                currentSample?.variability = 512 + factor * 64 + Int((higher >> 2) & 0b111111)
            } else {
                var variability = Int(lower & 0b01110000)
                variability <<= 2
                variability |= Int((higher >> 2) & 0b111111)
                currentSample?.variability = variability
            }
        } else {
            // Shift right by 1 because the first bit is a flag
            currentSample?.stepCount = Int((lower & 0b11111110) >> 1)
            currentSample?.variability = Int(higher) * Int(higher) * 64
            currentSample?.maxVariability = 10000
        }
    }
    
    /// Check if byte is a valid packet flag
    /// Source: ActivityFileParser.java#L142-L148
    private func isValidFlag(_ value: UInt8) -> Bool {
        [0xCE, 0xDD, 0xCB, 0xCC, 0xCF, 0xD6, 0xE2].contains(value)
    }
    
    /// Finish current sample and start a new one
    /// Source: ActivityFileParser.java#L234-L244
    private func finishCurrentPacket() {
        if let sample = currentSample {
            let entry = ActivityEntry(
                id: sample.id,
                timestamp: currentTimestamp,
                stepCount: sample.stepCount,
                heartRate: sample.heartRate,
                heartRateQuality: heartRateQuality,
                variability: sample.variability,
                maxVariability: sample.maxVariability,
                calories: sample.calories,
                isActive: sample.isActive,
                wearingState: wearingState
            )
            samples.append(entry)
            currentTimestamp += 60 // Each sample is 1 minute apart
        }
        
        currentSample = MutableActivityEntry(id: currentId)
        currentId += 1
    }
    
    /// Reset parser state
    private func resetState() {
        heartRateQuality = 0
        wearingState = .wearing
        currentTimestamp = 0
        currentSample = nil
        currentId = 1
        samples = []
        spo2Samples = []
        workoutSummaries = []
    }
}

// MARK: - Mutable Activity Entry (Internal Builder)

private struct MutableActivityEntry {
    let id: Int
    var stepCount: Int = 0
    var heartRate: Int = 0
    var variability: Int = 0
    var maxVariability: Int = 0
    var calories: Int = 0
    var isActive: Bool = false
}

// MARK: - ByteBuffer Reader Helper

/// Simple byte buffer reader for parsing activity data
private final class ByteBufferReader {
    private let data: Data
    var position: Int = 0
    
    var count: Int { data.count }
    
    init(data: Data) {
        self.data = data
    }
    
    func getByte() -> UInt8? {
        guard position < data.count else { return nil }
        let byte = data[position]
        position += 1
        return byte
    }
    
    func peekByte() -> UInt8? {
        guard position < data.count else { return nil }
        return data[position]
    }
    
    func peekByteAt(offset: Int) -> UInt8? {
        let targetPos = position + offset
        guard targetPos >= 0 && targetPos < data.count else { return nil }
        return data[targetPos]
    }
    
    func getUInt16() -> UInt16? {
        guard position + 2 <= data.count else { return nil }
        let value = UInt16(data[position]) | (UInt16(data[position + 1]) << 8)
        position += 2
        return value
    }
    
    func getInt16() -> Int16? {
        guard let unsigned = getUInt16() else { return nil }
        return Int16(bitPattern: unsigned)
    }
    
    func getUInt32() -> UInt32? {
        guard position + 4 <= data.count else { return nil }
        let value = UInt32(data[position]) |
                    (UInt32(data[position + 1]) << 8) |
                    (UInt32(data[position + 2]) << 16) |
                    (UInt32(data[position + 3]) << 24)
        position += 4
        return value
    }
    
    func getBytes(count: Int) -> [UInt8]? {
        guard position + count <= data.count else { return nil }
        let bytes = Array(data[position..<(position + count)])
        position += count
        return bytes
    }
    
    func skip(_ count: Int) {
        position = min(position + count, data.count)
    }
}

// MARK: - Errors

enum ActivityParserError: Error, LocalizedError {
    case fileTooSmall
    case invalidVersion(Int)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .fileTooSmall:
            return "Activity file is too small to parse"
        case .invalidVersion(let version):
            return "Unsupported activity file version: \(version)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
