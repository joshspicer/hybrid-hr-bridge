# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS companion app for Fossil/Skagen Hybrid HR smartwatches, implementing the reverse-engineered Bluetooth protocol from Gadgetbridge. Written in Swift/SwiftUI targeting iOS devices (Bluetooth won't work in simulator).

## Build and Test Commands

### Building
```bash
cd hybridHRBridge
xcodebuild -project hybridHRBridge.xcodeproj -scheme hybridHRBridge -configuration Debug
```

### Running Tests
```bash
# Run all tests
cd hybridHRBridge
xcodebuild test -project hybridHRBridge.xcodeproj -scheme hybridHRBridge -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test
xcodebuild test -project hybridHRBridge.xcodeproj -scheme hybridHRBridge -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:hybridHRBridgeTests/TestClassName/testMethodName
```

Note: Core Bluetooth features require a physical iOS device. Tests that don't involve Bluetooth can run in simulator.

## Code Architecture

### Manager Layer (Single Responsibility Pattern)

The app uses a hierarchical manager architecture with clear separation of concerns:

**WatchManager** (top-level coordinator)
- Entry point for all watch operations
- Coordinates between sub-managers
- Handles device persistence and auto-reconnection
- Location: `Services/WatchManager.swift`

**BluetoothManager** (BLE abstraction)
- CoreBluetooth wrapper providing async/await API
- Device discovery and connection state management
- Characteristic read/write operations with completion handlers
- Location: `Bluetooth/BluetoothManager.swift`

**AuthenticationManager** (crypto handshake)
- AES-128 CBC authentication protocol
- Manages phone/watch random numbers for IV generation
- CRITICAL: Must call `verifyAuthentication()` before EVERY encrypted file operation to refresh randoms (prevents IV reuse)
- Location: `Protocol/AuthenticationManager.swift`

**FileTransferManager** (file protocol)
- Implements file put/get protocol (commands 0x01, 0x03)
- Encrypted file reads (two-phase: lookup + encrypted get)
- AES-CTR decryption with IV incrementing
- CRC32 validation for integrity
- Location: `Protocol/FileTransferManager.swift`

**ActivityDataManager** (fitness data)
- Fetches and parses activity files (steps, HR, SpO2, workouts)
- Implements ActivityFileParser format (version 22)
- Location: `Services/ActivityDataManager.swift`

**VibrationManager** (haptics)
- Controls watch vibration patterns via 0x0600 file handle
- Location: `Protocol/VibrationManager.swift`

**MusicControlManager** (media control)
- Music info updates via 0x0400 file handle
- Location: `Protocol/MusicControlManager.swift`

### Protocol Implementation Pattern

All protocol operations follow this flow:
1. **Authentication** - Must be done first, establishes phone/watch randoms
2. **Operation** - File transfer, configuration read, etc.
3. **Validation** - CRC32 check on received data

For encrypted reads specifically:
1. Call `authManager.verifyAuthentication()` to get fresh randoms
2. Build IV from randoms: `IV[2-7] = phone[0-5], IV[9-15] = watch[0-6]`
3. Phase 1: File lookup (command 0x02) to resolve dynamic handle
4. Phase 2: Encrypted get (command 0x01) with AES-CTR decryption
5. Validate decrypted data CRC32 against completion response

### Key Protocol Details

**File Handles** (`Protocol/FileHandle.swift`)
- 16-bit values: `(major << 8) | minor`
- Common handles: 0x0100 (activity), 0x0400 (music), 0x0600 (vibration), 0x0800 (config), 0x0900 (notifications)

**Characteristics** (`Bluetooth/FossilConstants.swift`)
- 3dda0002: Connection parameters
- 3dda0003: File operations (put/get commands)
- 3dda0004: File data transfer
- 3dda0005: Authentication
- 3dda0006: Background events

**Little-Endian Byte Order**
- All multi-byte integers in the protocol are little-endian
- Use `ByteBuffer` utility for proper byte ordering

**CRC32 Algorithm** (`Utilities/CRC32.swift`)
- Standard IEEE 802.3 polynomial (0xEDB88320)
- Initial: 0xFFFFFFFF, Final XOR: 0xFFFFFFFF
- Validates both lookup data and decrypted file contents

### Authentication Flow

Five-step handshake (AES-128 CBC with zero IV):
1. Phone → Watch: Start sequence with 8 random bytes
2. Watch → Phone: 16 encrypted bytes (watch random + phone random echoed)
3. Phone: Decrypt, verify echo, swap halves, re-encrypt
4. Phone → Watch: 16 encrypted bytes (swapped randoms)
5. Watch → Phone: Status (0x00 = success)

The phone/watch randoms from this handshake are used to construct IVs for all subsequent encrypted file operations. **Must re-authenticate before each encrypted read to avoid IV reuse.**

### Activity Data Parsing

Activity file format (version 22):
- 52-byte header with metadata
- Variable-length TLV-style entries
- Packet types: 0xCE (main activity), 0xE0 (workout), 0xD6 (SpO2)
- Step count encoding: bit 0 of lower variability byte determines if steps are in bits 1-3 (if set) or bits 1-7 (if unset)

## Critical Protocol Requirements

1. **IV Freshness**: Call `verifyAuthentication()` before EVERY encrypted file operation. Reusing IVs causes decryption to fail.

2. **CRC Validation**: The CRC in completion responses is for the DECRYPTED data, not the encrypted bytes received.

3. **Packet Headers**: After AES-CTR decryption, strip the first byte (0x80 = last packet, 0x00 = more) before adding to file buffer.

4. **Configuration Files**: Have 12-byte header and 4-byte trailer that must be stripped before parsing TLV items.

5. **Byte Order**: All protocol integers are little-endian. Use ByteBuffer utility.

## Reference Documentation

`docs/PROTOCOL_SPECIFICATION.md` - Comprehensive protocol specification extracted from Gadgetbridge source. Cross-reference with Gadgetbridge when implementing new features.

Primary source: [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) (Java implementation on Android)

## Device Secret Key

The app requires a 16-byte AES key extracted from Gadgetbridge during initial pairing. See README.md for extraction instructions using ADB.

## ANCS Notification Support

The app can forward iOS system notifications to the watch via ANCS (Apple Notification Center Service). Users must enable "Share System Notifications" in iOS Settings > Bluetooth > [device] for this to work. The `BluetoothManager.ancsAuthorized` property tracks this state.
