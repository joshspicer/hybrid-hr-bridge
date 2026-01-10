import Foundation

/// Battery information parsed from configuration file
/// Source: ConfigurationPutRequest.BatteryConfigItem (Gadgetbridge)
struct BatteryStatus: Equatable {
    let percentage: Int
    let voltageMillivolts: Int
}
