# Hybrid HR Bridge - iOS Implementation Guide

## Overview

This guide outlines the iOS implementation architecture for communicating with Fossil/Skagen Hybrid HR watches over Bluetooth Low Energy.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                            │
├─────────────────────────────────────────────────────────────────┤
│  DeviceListView  │  WatchFaceView  │  NotificationSettingsView  │
└────────┬─────────┴────────┬────────┴────────────┬───────────────┘
         │                  │                      │
         ▼                  ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                      WatchManager                               │
│  (ObservableObject - manages device state & coordinates ops)    │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ NotificationSvc │ │   TimeSyncSvc   │ │   AppManager    │
└────────┬────────┘ └────────┬────────┘ └────────┬────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FileTransferManager                          │
│        (Handles file put/get protocol over BLE)                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌─────────────────────────────────────────────────────────────────┐
│                    AuthenticationManager                        │
│           (AES-128 CBC challenge-response)                      │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌─────────────────────────────────────────────────────────────────┐
│                     BluetoothManager                            │
│    (CoreBluetooth - scan, connect, characteristic R/W)          │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
hybridHRBridge/
├── hybridHRBridgeApp.swift
├── ContentView.swift
├── Bluetooth/
│   ├── BluetoothManager.swift       # CoreBluetooth wrapper
│   ├── FossilConstants.swift        # UUIDs, handles, constants
│   └── BLECharacteristic.swift      # Characteristic helpers
├── Protocol/
│   ├── AuthenticationManager.swift  # AES auth flow
│   ├── FileTransferManager.swift    # File put/get operations
│   ├── FileHandle.swift             # File handle enum
│   └── RequestBuilder.swift         # Protocol message builders
├── Services/
│   ├── NotificationService.swift    # Push notifications
│   ├── TimeSyncService.swift        # Time synchronization
│   └── AppInstallService.swift      # Watch app installation
├── Models/
│   ├── WatchDevice.swift            # Device model
│   ├── Notification.swift           # Notification model
│   └── WatchApp.swift               # Watch app model
├── Views/
│   ├── DeviceListView.swift         # Device discovery UI
│   ├── DeviceDetailView.swift       # Connected device UI
│   ├── NotificationSettingsView.swift
│   └── WatchFaceEditorView.swift
└── Utilities/
    ├── CRC32.swift                  # CRC32/CRC32C implementation
    ├── ByteBuffer.swift             # Little-endian byte helpers
    └── AESCrypto.swift              # AES encryption helpers
```

## Implementation Phases

### Phase 1: Bluetooth Foundation
- [x] Document protocol specification
- [ ] Implement `BluetoothManager` with CoreBluetooth
- [ ] Define `FossilConstants` (UUIDs, file handles)
- [ ] Basic device discovery and connection

### Phase 2: Authentication
- [ ] Implement AES-128 CBC encryption
- [ ] Build authentication challenge-response flow
- [ ] Store/retrieve device secret key from Keychain

### Phase 3: File Transfer Protocol
- [ ] Implement file put request builder
- [ ] Implement file get request builder
- [ ] Handle response parsing
- [ ] Support encrypted file transfers

### Phase 4: Core Features
- [ ] Time synchronization
- [ ] Push notifications
- [ ] Notification dismiss

### Phase 5: Advanced Features
- [ ] Watch face upload
- [ ] Custom app installation
- [ ] Complication editing

## Key Implementation Notes

### Byte Order
All multi-byte values use **little-endian** byte order.

### MTU Size
Request MTU of 512 bytes for efficient file transfers.

### Request Queue
Requests must be serialized - only one operation at a time.

### Background Mode
For notification forwarding, enable:
- `bluetooth-central` background mode
- State restoration in CoreBluetooth

## External Dependencies

- **CryptoKit** (iOS 13+): AES encryption
- **CoreBluetooth**: BLE communication
- **UserNotifications**: iOS notification access

## References

- [Protocol Specification](./PROTOCOL_SPECIFICATION.md)
- [Gadgetbridge Source](https://codeberg.org/Freeyourgadget/Gadgetbridge)
- [Fossil HR SDK](https://github.com/dakhnod/Fossil-HR-SDK)
