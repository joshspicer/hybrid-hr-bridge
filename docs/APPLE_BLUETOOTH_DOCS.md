# Apple CoreBluetooth Documentation Cache

**Last Updated:** January 9, 2026  
**Purpose:** Local reference for iOS Bluetooth Low Energy (BLE) development in the Hybrid HR Bridge app.

This document contains key information extracted from Apple Developer Documentation for CoreBluetooth, relevant to this project's BLE communication with Fossil/Skagen Hybrid HR watches.

---

## Table of Contents

1. [Framework Overview](#1-framework-overview)
2. [CBCentralManager - Device Discovery & Connection](#2-cbcentralmanager---device-discovery--connection)
3. [CBPeripheral - Service & Characteristic Discovery](#3-cbperipheral---service--characteristic-discovery)
4. [Reading, Writing & Notifications](#4-reading-writing--notifications)
5. [CBCharacteristicProperties](#5-cbcharacteristicproperties)
6. [CBUUID and CBService](#6-cbuuid-and-cbservice)
7. [Error Handling (CBError)](#7-error-handling-cberror)
8. [Background Execution & State Restoration](#8-background-execution--state-restoration)
9. [Info.plist Requirements](#9-infoplist-requirements)
10. [Best Practices Summary](#10-best-practices-summary)

---

## 1. Framework Overview

**Source:** [CoreBluetooth Documentation](https://developer.apple.com/documentation/corebluetooth/)

The Core Bluetooth framework provides the classes needed for apps to communicate with Bluetooth-equipped low energy (LE) devices.

### Key Points

- **Don't subclass** any CoreBluetooth classes - overriding is not supported and results in undefined behavior
- Core Bluetooth background execution modes aren't supported in iPad apps running on macOS
- **iOS 13+:** Apps must include `NSBluetoothAlwaysUsageDescription` in Info.plist or they will crash
- **iOS 12 and earlier:** Use `NSBluetoothPeripheralUsageDescription`

### Availability

- iOS 5.0+, iPadOS 5.0+, macOS 10.7+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

---

## 2. CBCentralManager - Device Discovery & Connection

**Source:** [CBCentralManager Documentation](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/)

`CBCentralManager` objects manage discovered or connected remote peripheral devices (represented by `CBPeripheral` objects), including scanning for, discovering, and connecting to advertising peripherals.

### Setup

```swift
import CoreBluetooth

class BLECentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    var discoveredPeripheral: CBPeripheral?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
}
```

### CBCentralManagerDelegate Methods

```swift
// REQUIRED: Called when the central manager's state updates
func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn {
        // Start scanning for peripherals (nil = all, or specify service UUIDs)
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    } else {
        // Handle other states: .poweredOff, .unauthorized, .unsupported, etc.
    }
}

// Called when a peripheral is discovered
func centralManager(_ central: CBCentralManager, 
                   didDiscover peripheral: CBPeripheral, 
                   advertisementData: [String : Any], 
                   rssi RSSI: NSNumber) {
    // Save reference and connect
    discoveredPeripheral = peripheral
    discoveredPeripheral?.delegate = self
    centralManager.stopScan()
    centralManager.connect(peripheral, options: nil)
}

// Called when connection succeeds
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    // Discover services
    peripheral.discoverServices(nil) // nil for all, or specify UUIDs
}

// Called when connection fails
func centralManager(_ central: CBCentralManager, 
                   didFailToConnect peripheral: CBPeripheral, 
                   error: Error?) {
    // Handle connection failure
}

// Called when disconnected
func centralManager(_ central: CBCentralManager, 
                   didDisconnectPeripheral peripheral: CBPeripheral, 
                   error: Error?) {
    // Handle disconnection, optionally reconnect
}
```

### CBManagerState Values

| State | Description |
|-------|-------------|
| `.poweredOn` | Bluetooth is on and available |
| `.poweredOff` | Bluetooth is turned off |
| `.unauthorized` | App not authorized for Bluetooth |
| `.unsupported` | Device doesn't support BLE |
| `.resetting` | Connection momentarily lost |
| `.unknown` | State unknown |

### Scanning Options

- `CBCentralManagerScanOptionAllowDuplicatesKey`: Set to `false` unless you need repeated discovery events
- Use specific service UUIDs in `scanForPeripherals(withServices:)` for efficiency and power savings

---

## 3. CBPeripheral - Service & Characteristic Discovery

**Source:** [CBPeripheral Documentation](https://developer.apple.com/documentation/corebluetooth/cbperipheral/)

`CBPeripheral` represents remote peripheral devices. Peripherals use UUIDs to identify themselves and may contain one or more services.

### Hierarchy

```
CBPeripheral
└── CBService (one or more)
    └── CBCharacteristic (one or more)
        └── CBDescriptor (optional)
```

### CBPeripheralDelegate Methods

```swift
// Called after service discovery
func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let services = peripheral.services else { return }
    for service in services {
        // Discover characteristics for each service
        peripheral.discoverCharacteristics(nil, for: service)
    }
}

// Called after characteristic discovery
func peripheral(_ peripheral: CBPeripheral, 
               didDiscoverCharacteristicsFor service: CBService, 
               error: Error?) {
    guard let characteristics = service.characteristics else { return }
    for characteristic in characteristics {
        // Work with discovered characteristics
        if characteristic.uuid == CBUUID(string: "YOUR-UUID-HERE") {
            // Read, write, or subscribe as needed
        }
    }
}
```

### Important: Always set the delegate before discovery

```swift
peripheral.delegate = self
peripheral.discoverServices([serviceUUID])
```

---

## 4. Reading, Writing & Notifications

### Reading Values

```swift
// Initiate read
peripheral.readValue(for: characteristic)

// Receive value in delegate
func peripheral(_ peripheral: CBPeripheral, 
               didUpdateValueFor characteristic: CBCharacteristic, 
               error: Error?) {
    if let data = characteristic.value {
        // Process received data
    }
}
```

### Writing Values

```swift
// Write with response (reliable)
peripheral.writeValue(data, for: characteristic, type: .withResponse)

// Write without response (faster, no confirmation)
peripheral.writeValue(data, for: characteristic, type: .withoutResponse)

// Receive write confirmation (only for .withResponse)
func peripheral(_ peripheral: CBPeripheral, 
               didWriteValueFor characteristic: CBCharacteristic, 
               error: Error?) {
    if let error = error {
        // Handle write error
    } else {
        // Write successful
    }
}
```

### Chunked Writes for Large Data

BLE characteristics have a maximum write size. Check and chunk accordingly:

```swift
let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
var offset = 0

while offset < data.count {
    let chunkSize = min(mtu, data.count - offset)
    let chunk = data.subdata(in: offset..<(offset + chunkSize))
    peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
    // Wait for didWriteValueFor callback before sending next chunk
    offset += chunkSize
}
```

### Subscribing to Notifications

```swift
// Subscribe
peripheral.setNotifyValue(true, for: characteristic)

// Unsubscribe
peripheral.setNotifyValue(false, for: characteristic)

// Notification state changed
func peripheral(_ peripheral: CBPeripheral, 
               didUpdateNotificationStateFor characteristic: CBCharacteristic, 
               error: Error?) {
    if characteristic.isNotifying {
        // Successfully subscribed
    }
}

// Values received via didUpdateValueFor (same as read)
func peripheral(_ peripheral: CBPeripheral, 
               didUpdateValueFor characteristic: CBCharacteristic, 
               error: Error?) {
    // Handle notification data
}
```

---

## 5. CBCharacteristicProperties

**Source:** [CBCharacteristicProperties Documentation](https://developer.apple.com/documentation/corebluetooth/cbcharacteristicproperties/)

`CBCharacteristicProperties` is an `OptionSet` indicating what operations a characteristic supports.

### Available Properties

| Property | Description |
|----------|-------------|
| `.broadcast` | Permits broadcasting |
| `.read` | Permits reading the value |
| `.writeWithoutResponse` | Permits writing without response |
| `.write` | Permits writing with response |
| `.notify` | Permits notifications (no acknowledgment) |
| `.indicate` | Permits indications (with acknowledgment) |
| `.authenticatedSignedWrites` | Permits signed writes |
| `.extendedProperties` | Has extended properties |
| `.notifyEncryptionRequired` | Notify requires encryption |
| `.indicateEncryptionRequired` | Indicate requires encryption |

### Checking Support

```swift
// Check before performing operations
if characteristic.properties.contains(.read) {
    peripheral.readValue(for: characteristic)
}

if characteristic.properties.contains(.write) {
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
}

if characteristic.properties.contains(.writeWithoutResponse) {
    peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
}

if characteristic.properties.contains(.notify) {
    peripheral.setNotifyValue(true, for: characteristic)
}

if characteristic.properties.contains(.indicate) {
    peripheral.setNotifyValue(true, for: characteristic)
}
```

---

## 6. CBUUID and CBService

**Source:** [CBService Documentation](https://developer.apple.com/documentation/corebluetooth/cbservice/)

### Creating UUIDs

```swift
// Standard 16-bit UUID (e.g., Heart Rate Service)
let heartRateServiceUUID = CBUUID(string: "180D")

// Custom 128-bit UUID (common for proprietary protocols like Fossil)
let fossilServiceUUID = CBUUID(string: "3dda0001-957f-7d4a-34a6-74696673696d")
```

### CBService

`CBService` objects represent services of a remote peripheral. Services are either primary or secondary and may contain multiple characteristics.

```swift
// Access service UUID
let uuid = service.uuid

// Access discovered characteristics
if let characteristics = service.characteristics {
    for characteristic in characteristics {
        // Work with characteristic
    }
}
```

---

## 7. Error Handling (CBError)

**Source:** [CBError Documentation](https://developer.apple.com/documentation/corebluetooth/cberror-swift.struct/)

### Common Error Codes

| Error Code | Description |
|------------|-------------|
| `.connectionFailed` | The connection failed (iOS 7.1+) |
| `.connectionTimeout` | The connection timed out (iOS 6.0+) |
| `.connectionLimitReached` | Max connections reached (iOS 9.0+) |
| `.unknown` | Unknown error |
| `.invalidParameters` | Invalid parameters |
| `.invalidHandle` | Invalid handle |
| `.notConnected` | Not connected |
| `.outOfSpace` | Out of space |
| `.operationCancelled` | Operation cancelled |
| `.peerRemovedPairingInformation` | Peer removed pairing info |
| `.encryptionTimedOut` | Encryption timed out |

### Handling Errors

```swift
func centralManager(_ central: CBCentralManager, 
                   didFailToConnect peripheral: CBPeripheral, 
                   error: Error?) {
    if let cbError = error as? CBError {
        switch cbError.code {
        case .connectionFailed:
            // Retry connection or notify user
            break
        case .connectionTimeout:
            // Retry or prompt user to move closer
            break
        case .connectionLimitReached:
            // Disconnect another peripheral first
            break
        default:
            // Handle other errors
            break
        }
    }
}

func centralManager(_ central: CBCentralManager, 
                   didDisconnectPeripheral peripheral: CBPeripheral, 
                   error: Error?) {
    if let error = error {
        // Unexpected disconnection
    }
    // Optionally attempt reconnection
}
```

---

## 8. Background Execution & State Restoration

**Source:** [TN3115: Bluetooth State Restoration](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules/)

### Enabling Background Modes

In Xcode:
1. Select your target → Signing & Capabilities
2. Add "Background Modes" capability
3. Check "Uses Bluetooth LE accessories"

### Configuring State Restoration

```swift
// Initialize with restoration identifier
let centralManager = CBCentralManager(
    delegate: self, 
    queue: nil, 
    options: [
        CBCentralManagerOptionRestoreIdentifierKey: "com.hybridHRBridge.CentralManager"
    ]
)
```

### Implementing State Restoration

```swift
func centralManager(_ central: CBCentralManager, 
                   willRestoreState dict: [String : Any]) {
    // Restore connected peripherals
    if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
        for peripheral in peripherals {
            // Re-assign delegate
            peripheral.delegate = self
            // Store reference
            // Reconnect if needed
        }
    }
    
    // Restore scanning services
    if let scanServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
        // Resume scanning if needed
    }
}
```

### App Relaunch Rules (TN3115)

iOS will relaunch your app in the background for pending Core Bluetooth requests **only if**:
- App was scanning, connecting, or subscribed to notifications
- The corresponding Bluetooth event occurred
- User has **not** force-quit the app
- Device has been unlocked at least once since reboot
- Bluetooth is enabled

**Important (iOS 26+):** Only apps using `AccessorySetupKit` will be relaunched for Bluetooth events.

### Connection Options for Background Notifications

```swift
centralManager.connect(peripheral, options: [
    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
    CBConnectPeripheralOptionNotifyOnNotificationKey: true
])
```

---

## 9. Info.plist Requirements

**Source:** [NSBluetoothAlwaysUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription/)

### Required Keys

Add these to your `Info.plist`:

```xml
<!-- Required for iOS 13+ -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to connect to and communicate with your Fossil/Skagen Hybrid HR watch.</string>

<!-- Required for iOS 12 and earlier (include for compatibility) -->
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to connect to and communicate with your Fossil/Skagen Hybrid HR watch.</string>
```

### Background Modes (if using background BLE)

```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

**Warning:** Your app will crash if these keys are missing when using Bluetooth APIs.

---

## 10. Best Practices Summary

### Connection & Scanning

- ✅ Always check `central.state == .poweredOn` before scanning
- ✅ Use specific service UUIDs when scanning for efficiency
- ✅ Stop scanning after discovering desired peripheral
- ✅ Set `CBCentralManagerScanOptionAllowDuplicatesKey` to `false` unless needed
- ✅ Handle all delegate callbacks including failures and disconnects
- ✅ Release references to peripherals when done

### Discovery

- ✅ Set `peripheral.delegate` before calling discovery methods
- ✅ Use specific UUIDs for faster discovery
- ✅ Check for errors in all delegate callbacks
- ✅ Never force-unwrap optionals

### Reading & Writing

- ✅ Check `characteristic.properties` before attempting operations
- ✅ Use `.withResponse` for reliable writes
- ✅ Check `maximumWriteValueLength(for:)` before writing
- ✅ Chunk large data transfers
- ✅ Wait for `didWriteValueFor` before sending next chunk

### Background & State Restoration

- ✅ Enable Background Modes capability
- ✅ Use restoration identifier in `CBCentralManager` initialization
- ✅ Implement `willRestoreState` delegate method
- ✅ Re-assign delegates after restoration
- ✅ Minimize background work to avoid suspension

### Error Handling

- ✅ Handle `CBError` codes appropriately
- ✅ Implement retry logic with limits
- ✅ Inform users of persistent failures
- ✅ For `.connectionLimitReached`, disconnect unused peripherals

---

## Project-Specific: Fossil Hybrid HR UUIDs

For reference, these are the UUIDs used by Fossil Hybrid HR watches (defined in `FossilConstants.swift`):

```swift
// Main Service UUID
static let serviceUUID = CBUUID(string: "3dda0001-957f-7d4a-34a6-74696673696d")

// Characteristic UUIDs
static let deviceInfoCharacteristicUUID = CBUUID(string: "3dda0002-957f-7d4a-34a6-74696673696d")
static let fileOperationsCharacteristicUUID = CBUUID(string: "3dda0003-957f-7d4a-34a6-74696673696d")
static let fileDataCharacteristicUUID = CBUUID(string: "3dda0004-957f-7d4a-34a6-74696673696d")
static let configurationCharacteristicUUID = CBUUID(string: "3dda0005-957f-7d4a-34a6-74696673696d")
static let commandCharacteristicUUID = CBUUID(string: "3dda0006-957f-7d4a-34a6-74696673696d")
```

---

## References

- [Core Bluetooth Documentation](https://developer.apple.com/documentation/corebluetooth/)
- [CBCentralManager](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/)
- [CBPeripheral](https://developer.apple.com/documentation/corebluetooth/cbperipheral/)
- [CBCharacteristic](https://developer.apple.com/documentation/corebluetooth/cbcharacteristic/)
- [TN3115: Bluetooth State Restoration](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules/)
- [Core Bluetooth Programming Guide (Archive)](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/AboutCoreBluetooth/Introduction.html)
