# Fossil/Skagen Hybrid HR Bluetooth Protocol Specification

> Extracted from [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) source code
> IMPORTANT: ALWAYS cross-reference claims in this doucment with the original primary source.  This document is for convenience only and may contain errors.

---

## Table of Contents

1. [BLE UUIDs](#1-ble-uuids)
2. [File Handle System](#2-file-handle-system)
3. [Authentication Protocol](#3-authentication-protocol)
4. [Notification Format](#4-notification-format)
5. [Time Synchronization](#5-time-synchronization)
6. [Watch Face/App Upload](#6-watch-faceapp-upload)
7. [Protocol Message Formats](#7-protocol-message-formats)
8. [Connection Parameters](#8-connection-parameters)
9. [Activity Data Fetch Protocol](#9-activity-data-fetch-protocol)
10. [Encrypted File Read Protocol (Detailed)](#10-encrypted-file-read-protocol-detailed)

---

## 1. BLE UUIDs

### Service UUID

| UUID | Purpose | Source |
|------|---------|--------|
| `3dda0001-957f-7d4a-34a6-74696673696d` | Main Service UUID | [QHybridCoordinator.java#L64-L80](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/devices/qhybrid/QHybridCoordinator.java#L64-L80) |

### Characteristic UUIDs

| UUID | Purpose | Source |
|------|---------|--------|
| `3dda0002-957f-7d4a-34a6-74696673696d` | Connection Parameters / Pairing | [Request.java#L53](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/Request.java#L53) |
| `3dda0003-957f-7d4a-34a6-74696673696d` | File Operations (Put/Get) | [FilePutRawRequest.java#L237](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FilePutRawRequest.java#L237) |
| `3dda0004-957f-7d4a-34a6-74696673696d` | File Data Transfer | [FileEncryptedPutRequest.java#L89-L107](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/file/FileEncryptedPutRequest.java#L89-L107) |
| `3dda0005-957f-7d4a-34a6-74696673696d` | Authentication | [AuthenticationRequest.java#L22-L28](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/authentication/AuthenticationRequest.java#L22-L28) |
| `3dda0006-957f-7d4a-34a6-74696673696d` | Background Events | [FossilWatchAdapter.java#L641-L652](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil/FossilWatchAdapter.java#L641-L652) |
| `00002a37-0000-1000-8000-00805f9b34fb` | Heart Rate Measurement | [FossilWatchAdapter.java#L649](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil/FossilWatchAdapter.java#L649) |

---

## 2. File Handle System

All data transfers use a file-based system with major/minor handles.

**Source:** /Users/josh/git/Gadgetbridge/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/file/FileHandle.java#L1-L74

| Handle Name | Major | Minor | Hex Value | Purpose |
|-------------|-------|-------|-----------|---------|
| `OTA_FILE` | 0x00 | 0x00 | `0x0000` | Firmware updates |
| `ACTIVITY_FILE` | 0x01 | 0x00 | `0x0100` | Activity/fitness data |
| `HARDWARE_LOG_FILE` | 0x02 | 0x00 | `0x0200` | Debug logs |
| `FONT_FILE` | 0x03 | 0x00 | `0x0300` | Font files |
| `MUSIC_INFO` | 0x04 | 0x00 | `0x0400` | Music control |
| `UI_CONTROL` | 0x05 | 0x00 | `0x0500` | UI state |
| `HAND_ACTIONS` | 0x06 | 0x00 | `0x0600` | Button configuration |
| `ASSET_BACKGROUND_IMAGES` | 0x07 | 0x00 | `0x0700` | Watchface backgrounds |
| `ASSET_NOTIFICATION_IMAGES` | 0x07 | 0x01 | `0x0701` | Notification icons |
| `ASSET_TRANSLATIONS` | 0x07 | 0x02 | `0x0702` | Localization strings |
| `ASSET_REPLY_IMAGES` | 0x07 | 0x03 | `0x0703` | Quick reply images |
| `CONFIGURATION` | 0x08 | 0x00 | `0x0800` | Device configuration |
| `NOTIFICATION_PLAY` | 0x09 | 0x00 | `0x0900` | Push notifications |
| `ALARMS` | 0x0A | 0x00 | `0x0A00` | Alarm settings |
| `DEVICE_INFO` | 0x0B | 0x00 | `0x0B00` | Device information |
| `NOTIFICATION_FILTER` | 0x0C | 0x00 | `0x0C00` | Notification filtering |
| `WATCH_PARAMETERS` | 0x0E | 0x00 | `0x0E00` | Watch parameters |
| `LOOK_UP_TABLE` | 0x0F | 0x00 | `0x0F00` | Lookup tables |
| `RATE` | 0x10 | 0x00 | `0x1000` | Heart rate data |
| `REPLY_MESSAGES` | 0x13 | 0x00 | `0x1300` | Quick reply messages |
| `APP_CODE` | 0x15 | 0xFE | `0x15FE` | Watch apps/faces |

**Handle Calculation:** `(major << 8) | minor`

---

## 3. Authentication Protocol

The Fossil Hybrid HR uses **AES-128 CBC encryption** with a zero IV for the authentication handshake.

### Authentication Flow

**Source:** [VerifyPrivateKeyRequest.java#L40-L134](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/authentication/VerifyPrivateKeyRequest.java#L40-L134)

#### Step 1: Phone → Watch (Start Sequence)

```
Byte 0:    0x02 (request type)
Byte 1:    0x01 (auth command)
Byte 2:    0x01 (sub-command)
Bytes 3-10: 8 random bytes (phone random number)
```

#### Step 2: Watch → Phone (Encrypted Challenge)

Watch sends 16 encrypted bytes containing:
- Bytes 0-7: Watch random number
- Bytes 8-15: Phone random number (echoed back)

#### Step 3: Phone Decrypts & Swaps

```
1. Decrypt 16 bytes using AES/CBC/NoPadding with zero IV
2. Verify bytes 8-15 match the phone random number sent
3. Swap halves: bytes[0-7] ↔ bytes[8-15]
4. Re-encrypt using AES/CBC/NoPadding with zero IV
```

#### Step 4: Phone → Watch (Response)

```
Byte 0:     0x02 (response type)
Byte 1:     0x02 (auth response)
Byte 2:     0x01 (status)
Bytes 3-18: 16 encrypted bytes (swapped and re-encrypted)
```

#### Step 5: Watch → Phone (Authentication Result)

**Source:** [VerifyPrivateKeyRequest.java#L106-L110](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/authentication/VerifyPrivateKeyRequest.java#L106-L110)

```
Byte 0:     0x03 (response type)
Byte 1:     0x02 (auth result)
Byte 2:     Status code (0x00 = SUCCESS, other values indicate failure)
```

**Important:** Status code `0x00` indicates successful authentication. Any other value means authentication was rejected.

### Secret Key Storage

**Source:** [FossilHRWatchAdapter.java#L1621-L1640](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil_hr/FossilHRWatchAdapter.java#L1621-L1640)

- 16-byte AES key stored as 32-character hex string
- Key is device-specific and established during initial pairing

### File Encryption IV Generation

**Source:** [FileEncryptedGetRequest.java#L82-L107](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/file/FileEncryptedGetRequest.java#L82-L107)

```
IV[16] = {0}
IV[2-7]  = phoneRandomNumber[0-5]
IV[9-15] = watchRandomNumber[0-6]
IV[7]++
```

---

## 4. Notification Format

### Notification Types

**Source:** [NotificationType.java#L18-L37](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/notification/NotificationType.java#L18-L37)

| Type | Value | Description |
|------|-------|-------------|
| `INCOMING_CALL` | 1 | Active phone call |
| `TEXT` | 2 | SMS/Text message |
| `NOTIFICATION` | 3 | Generic notification |
| `EMAIL` | 4 | Email notification |
| `CALENDAR` | 5 | Calendar event |
| `MISSED_CALL` | 6 | Missed call |
| `DISMISS_NOTIFICATION` | 7 | Dismiss existing notification |

### Notification Payload Structure

**Source:** /Users/josh/git/Gadgetbridge/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/notification/PlayNotificationRequest.java#L48-L91

**File Handle:** `0x0900` (NOTIFICATION_PLAY)

```
Bytes 0-1:   Payload length (little-endian short, includes remaining bytes)
Byte 2:      Length buffer size (always 0x0A)
Byte 3:      Notification type (see table above)
Byte 4:      Flags
Byte 5:      UID length (0x04)
Byte 6:      Package CRC length (0x04)
Byte 7:      Title byte count (includes null terminator)
Byte 8:      Sender byte count (includes null terminator)
Byte 9:      Message byte count (includes null terminator; message truncated to 475 characters before encoding)
Bytes 10-13: Message ID (little-endian int)
Bytes 14-17: Package CRC32 (little-endian int)
[Title]      UTF-8 null-terminated string
[Sender]     UTF-8 null-terminated string
[Message]    UTF-8 null-terminated string
```

### Notification Filter Configuration

**Source:** [NotificationFilterPutHRRequest.java#L117-L134](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/notification/NotificationFilterPutHRRequest.java#L117-L134)

| Packet ID | Hex | Purpose |
|-----------|-----|---------|
| `PACKAGE_NAME` | 0x01 | Package name string |
| `SENDER_NAME` | 0x02 | Sender name |
| `PACKAGE_NAME_CRC` | 0x04 | CRC32 of package name |
| `GROUP_ID` | 0x80 | Group identifier |
| `APP_DISPLAY_NAME` | 0x81 | Display name |
| `ICON` | 0x82 | Icon reference |
| `PRIORITY` | 0xC1 | Notification priority |
| `MOVEMENT` | 0xC2 | Hand movement config |
| `VIBRATION` | 0xC3 | Vibration pattern |

---

## 5. Time Synchronization

### Configuration Item IDs

**Source:** [ConfigurationPutRequest.java#L32-L45](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/configuration/ConfigurationPutRequest.java#L32-L45)

| Config ID | Hex | Purpose |
|-----------|-----|---------|
| `CurrentStepCount` | 0x02 | Step counter |
| `DailyStepGoal` | 0x03 | Daily goal |
| `InactivityWarning` | 0x09 | Inactivity alert |
| `VibrationStrength` | 0x0A | Vibration level |
| **`TimeConfig`** | **0x0C** | **Time synchronization** |
| `BatteryConfig` | 0x0D | Battery info |
| `HeartRateMode` | 0x0E | HR measurement mode |
| `UnitsConfig` | 0x10 | Measurement units |
| `TimezoneOffset` | 0x11 | Timezone offset |
| `FitnessConfig` | 0x14 | Activity recognition |

### TimeConfigItem Structure (8 bytes)

**Source:** [ConfigurationPutRequest.java#L292-L337](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/configuration/ConfigurationPutRequest.java#L292-L337)

```
Bytes 0-3:  Unix epoch seconds (little-endian int32)
Bytes 4-5:  Milliseconds (little-endian int16)
Bytes 6-7:  Timezone offset in minutes (little-endian int16)
```

### Example Time Generation

**Source:** [FossilWatchAdapter.java#L306-L316](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil/FossilWatchAdapter.java#L306-L316)

```java
long millis = System.currentTimeMillis();
TimeZone zone = TimeZone.getDefault();

int epochSeconds = (int)(millis / 1000);
short millisPart = (short)(millis % 1000);
short offsetMinutes = (short)(zone.getOffset(millis) / 60000);
```

---

## 6. Watch Face/App Upload

### .wapp File Structure

**Source:** [FossilAppWriter.java#L63-L120](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/util/protobuf/FossilAppWriter.java#L63-L120)

**File Handle:** `0x15FE` (APP_CODE)

```
Bytes 0-1:   File handle (0xFE, 0x15)
Bytes 2-3:   File version (0x03, 0x00)
Bytes 4-7:   File offset (little-endian int, usually 0)
Bytes 8-11:  File size (little-endian int)
[File data]
Bytes N-N+3: CRC32C checksum
```

### App Metadata Structure

```
Byte 0:     App type (1 = watchface, 2 = app)
Bytes 1-2:  Version (major.minor)
Byte 3:     Unknown flag
...
Offset 88:  Start of code/data sections
```

### SDK Reference

For building custom watch apps, see [Fossil-HR-SDK](https://github.com/dakhnod/Fossil-HR-SDK)

---

## 7. Protocol Message Formats

### File Put Request (15-byte header)

**Source:** /Users/josh/git/Gadgetbridge/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FilePutRawRequest.java#L54-L134

**Characteristic:** `3dda0003`

```
Byte 0:     0x03 (file put command)
Bytes 1-2:  File handle (little-endian)
Bytes 3-6:  File offset (little-endian)
Bytes 7-10: File size (little-endian)
Bytes 11-14: File size (repeat, little-endian)
```

- Each data packet prefixes the payload with the sequential packet index (0, 1, 2, …) rather than a last-packet flag. Source: /Users/josh/git/Gadgetbridge/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FilePutRawRequest.java#L198-L216
- After a 0x08 acknowledgment, the phone must send a `0x04` file-close command containing the handle to finalize the transfer. Source: /Users/josh/git/Gadgetbridge/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FilePutRawRequest.java#L102-L136

### File Get Request (11-byte header)

**Source:** [FileGetRawRequest.java#L134-L148](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FileGetRawRequest.java#L134-L148)

**Characteristic:** `3dda0003`

```
Byte 0:     0x01 (file get command)
Byte 1:     Minor handle
Byte 2:     Major handle
Bytes 3-6:  Start offset (typically 0)
Bytes 7-10: End offset (0xFFFFFFFF for full file)
```

### Response Types

**Source:** [FileVerifyRequest.java#L45-L69](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FileVerifyRequest.java#L45-L69)

| Response (byte 0 & 0x0F) | Meaning |
|--------------------------|---------|
| 0x01 | File get init response |
| 0x03 | File put init response |
| 0x04 | File operation complete |
| 0x08 | Data chunk acknowledgment |
| 0x0A | Continuation/progress |

### Result Codes

**Source:** [ResultCode.java#L40-L71](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/ResultCode.java#L40-L71)

| Code | Name | Description |
|------|------|-------------|
| 0 | `SUCCESS` | Operation successful |
| 139 | `INPUT_DATA_INVALID` | Invalid input data |
| 140 | `NOT_AUTHENTICATE` | Authentication required |
| 141 | `SIZE_OVER_LIMIT` | File too large |

---

## 8. Connection Parameters

**Source:** [SetConnectionParametersRequest.java#L44-L46](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/connection/SetConnectionParametersRequest.java#L44-L46)

**Characteristic:** `3dda0002`

```
Bytes: {0x02, 0x09, 0x0C, 0x00, 0x0C, 0x00, 0x2D, 0x00, 0x58, 0x02}

Connection interval min: 0x000C (12) × 1.25ms = 15ms
Connection interval max: 0x000C (12) × 1.25ms = 15ms
Slave latency: 0x002D (45)
Supervision timeout: 0x0258 (600) × 10ms = 6 seconds
```

---

## 10. Encrypted File Read Protocol (Detailed)

This section documents the complete encrypted file read flow used for reading sensitive data like configuration (battery, device settings) and activity files.

### Overview

Reading encrypted files requires a **two-phase protocol**:
1. **Lookup Phase**: Resolve the static file handle to a dynamic handle
2. **Encrypted Get Phase**: Fetch and decrypt the file data using AES-CTR

**CRITICAL**: Each encrypted read operation requires fresh random numbers. Call `VerifyPrivateKeyRequest` (re-authentication handshake) before EVERY encrypted file operation to generate new phone/watch randoms. Using stale randoms causes IV reuse and decryption failure.

**Source:** [FileEncryptedLookupAndGetRequest.java](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/file/FileEncryptedLookupAndGetRequest.java)

### Phase 1: File Lookup

**Source:** [FileLookupRequest.java#L26-L60](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FileLookupRequest.java#L26-L60)

#### Request Format (3 bytes)

**Characteristic:** `3dda0003`

```
Byte 0:     0x02 (file lookup command)
Byte 1:     0xFF (lookup marker)
Byte 2:     Major handle (e.g., 0x08 for CONFIGURATION)
```

Example for CONFIGURATION file: `02 FF 08`

#### Lookup Responses

The lookup phase involves multiple responses across two characteristics:

**Response 1 on 3dda0003** (9 bytes):
```
Byte 0:      0x82 (0x02 | 0x80 = lookup response)
Byte 1:      0xFF
Byte 2:      Major handle echoed
Byte 3:      Status (0x00 = success)
Bytes 4-7:   Expected data size (little-endian uint32)
Byte 8:      0x00 padding
```

**Data on 3dda0004** (variable length):
```
Byte 0:      0x80 (data packet marker)
Bytes 1-2:   Resolved minor/major handle
Bytes 3-6:   File size (little-endian uint32)
Bytes 7-10:  CRC32 of lookup data
```

**Response 2 on 3dda0003** (12 bytes - completion):
```
Byte 0:      0x88 (0x08 | 0x80 = lookup complete)
Byte 1:      0xFF
Byte 2:      Major handle
Byte 3:      Status (0x00 = success)
Bytes 4-7:   Data size
Bytes 8-11:  CRC32 of received data
```

#### Extracting the Dynamic Handle

From the data packet on 3dda0004:
```swift
let handleValue = UInt16(data[1]) | (UInt16(data[2]) << 8)
let minor = UInt8(handleValue & 0xFF)
let major = UInt8((handleValue >> 8) & 0xFF)
```

### Phase 2: Encrypted Get

**Source:** [FileEncryptedGetRequest.java#L36-L140](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/file/FileEncryptedGetRequest.java#L36-L140)

#### Request Format (11 bytes)

**Characteristic:** `3dda0003`

```
Byte 0:      0x01 (file get command)
Byte 1:      Minor handle (from lookup)
Byte 2:      Major handle (from lookup)
Bytes 3-6:   Start offset (little-endian, typically 0x00000000)
Bytes 7-10:  End offset (little-endian, 0xFFFFFFFF for full file)
```

Example: `01 00 08 00 00 00 00 FF FF FF FF`

#### Get Response (on 3dda0003)

**Init Response** (9 bytes):
```
Byte 0:      0x81 (0x01 | 0x80 = get init response)
Byte 1:      Minor handle
Byte 2:      Major handle
Byte 3:      Status (0x00 = success)
Bytes 4-7:   File size (little-endian uint32)
Byte 8:      0x00 padding
```

**Completion Response** (12 bytes):
```
Byte 0:      0x88 (0x08 | 0x80 = get complete)
Byte 1:      Minor handle
Byte 2:      Major handle
Byte 3:      Status (0x00 = success)
Bytes 4-7:   File size
Bytes 8-11:  **Expected CRC32** of decrypted data
```

### AES-CTR Decryption

**Source:** [FileEncryptedGetRequest.java#L82-L140](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/file/FileEncryptedGetRequest.java#L82-L140)

#### IV Construction

The IV is built from the phone and watch random numbers generated during authentication:

```swift
var iv = Data(repeating: 0, count: 16)
// Copy phone random bytes 0-5 into IV positions 2-7
for i in 0..<6 {
    iv[2 + i] = phoneRandom[i]
}
// Increment byte at position 7
iv[7] = iv[7] &+ 1
// Copy watch random bytes 0-6 into IV positions 9-15
for i in 0..<7 {
    iv[9 + i] = watchRandom[i]
}
```

**Result**: `00 00 [phone0-5] 00 [watch0-6]` with phone[5]+1

#### Packet Decryption

Each encrypted packet on 3dda0004 must be decrypted:

**First Packet (packet 0)**:
- Use the original IV directly
- Decrypted byte 0 is the header:
  - `0x80` = last packet (MSB set)
  - `0x00-0x7F` = more packets coming
- Remaining bytes are payload

**Subsequent Packets**:
- IV must be incremented for each packet
- Increment amount is discovered from packet 1 (typically `0x1F`)
- For packet N: `IV[7] += incrementor * N`

**IV Incrementor Discovery** (for packet 1):
```swift
for summand in 0x1E...0x2F {
    let testIV = incrementedIV(from: originalIV, by: summand)
    let candidate = AES_CTR_decrypt(packet, key, testIV)
    
    // Check if header byte makes sense
    let header = candidate[0]
    let expectedHeader: UInt8 = (currentBufferSize + candidate.count - 1 == expectedFileSize) ? 0x81 : 0x01
    
    if header == expectedHeader {
        ivIncrementor = summand  // Found it!
        break
    }
}
```

### CRC32 Validation

**CRITICAL**: All file transfers include CRC32 validation to ensure data integrity.

#### CRC32 Algorithm

Uses the standard CRC-32 polynomial (IEEE 802.3):
- Polynomial: `0xEDB88320`
- Initial value: `0xFFFFFFFF`
- Final XOR: `0xFFFFFFFF`

```swift
extension Data {
    var crc32: UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in self {
            crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFFFFFF
    }
}
```

#### Where CRC Validation Occurs

1. **Lookup Phase**: CRC of lookup data (on 3dda0004) validated against CRC in completion response (3dda0003)
2. **Get Phase**: CRC of **decrypted** file data validated against CRC in completion response

```swift
// From completion response on 3dda0003
let expectedCRC = data.subdata(in: 8..<12).withUnsafeBytes { 
    $0.load(as: UInt32.self) 
}.littleEndian

// Compute CRC of decrypted file buffer
let actualCRC = fileBuffer.crc32

guard expectedCRC == actualCRC else {
    throw FileTransferError.invalidCRC
}
```

### Configuration File Parsing

**Source:** [ConfigurationGetRequest.java#L40-L73](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/configuration/ConfigurationGetRequest.java#L40-L73)

The CONFIGURATION file (handle 0x0800) contains device settings as a series of TLV (Type-Length-Value) items.

#### File Structure

```
Bytes 0-11:  File header (12 bytes)
[Payload]:   Configuration items (TLV format)
Last 4:      CRC32 or trailer
```

#### Configuration Item Format (TLV)

Each item in the payload:
```
Bytes 0-1:   Item ID (little-endian uint16)
Byte 2:      Data length
Bytes 3-N:   Item data
```

#### Parsing Loop

```swift
let payloadRange = 12..<(fileData.count - 4)
let payload = fileData.subdata(in: payloadRange)

var buffer = ByteBuffer(data: payload)
while buffer.remainingBytes > 0 {
    guard let itemId = buffer.getUInt16(),      // 2 bytes, little-endian
          let length = buffer.getUInt8(),        // 1 byte
          let data = buffer.getBytes(Int(length)) else {
        break
    }
    
    // Process item based on itemId
    switch itemId {
    case 0x0001: // CurrentTime
    case 0x0002: // StepCount
    case 0x000D: // BatteryConfig
        // ...
    }
}
```

#### Battery Config Item (ID 0x000D)

**Source:** [BatteryConfigItem.java](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/configuration/ConfigurationPutRequest.java#L190-L220)

```
Bytes 0-1:   Voltage in millivolts (little-endian uint16)
Byte 2:      Battery percentage (0-100)
Byte 3:      (Optional) Charging state
```

Parsing:
```swift
if itemId == 0x000D && data.count >= 3 {
    let voltage = UInt16(data[0]) | (UInt16(data[1]) << 8)
    let percentage = Int(data[2])
    // data[3] may contain charging state if present
}
```

### Complete Read Flow Example

```
1. [Phone] Call verifyAuthentication() to get fresh randoms
   └─ Generates new phoneRandom and watchRandom
   
2. [Phone] Build IV from randoms
   └─ IV = [00 00 phone[0-5] 00 watch[0-6]] with phone[5]+1

3. [Phone → Watch] Send lookup: 02 FF 08
   └─ On 3dda0003
   
4. [Watch → Phone] Lookup responses
   ├─ 3dda0003: 82 FF 08 00 0A 00 00 00 00 (expects 10 bytes)
   ├─ 3dda0004: 80 00 08 B5 00 00 00 [CRC] (handle=0x0800, size=181)
   └─ 3dda0003: 88 FF 08 00 0A 00 00 00 [CRC] (complete)

5. [Phone] Validate lookup CRC, extract dynamic handle (0x08, 0x00)

6. [Phone → Watch] Send encrypted get: 01 00 08 00 00 00 00 FF FF FF FF
   └─ On 3dda0003

7. [Watch → Phone] Get responses
   ├─ 3dda0003: 81 00 08 00 B5 00 00 00 00 (file size=181 bytes)
   ├─ 3dda0004: [182 encrypted bytes]
   └─ 3dda0003: 88 00 08 00 B5 00 00 00 [CRC] (complete + expected CRC)

8. [Phone] Decrypt packet using AES-CTR with generated IV
   └─ First byte of decrypted = 0x80 (last packet)
   └─ Remaining 181 bytes = file data

9. [Phone] Validate decrypted data CRC matches expected CRC

10. [Phone] Parse configuration TLV items
    └─ Extract battery info from item 0x000D
```

### Common Pitfalls

1. **IV Reuse**: MUST call `verifyAuthentication()` before each encrypted operation. Using the same phone/watch randoms twice causes CRC validation to fail because decryption produces garbage.

2. **Byte Order**: All multi-byte integers are **little-endian** throughout the protocol.

3. **CRC Scope**: The CRC in the completion response is for the **decrypted** data, not the encrypted bytes received.

4. **Packet Header**: After decryption, the first byte is a header (0x80 = last, 0x00 = more), NOT part of the file data. Strip it before adding to the buffer.

5. **File Structure**: Configuration files have a 12-byte header and 4-byte trailer that must be stripped before parsing TLV items.

---

## Key Source Files

| Component | File | Link |
|-----------|------|------|
| Main HR Adapter | `FossilHRWatchAdapter.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil_hr/FossilHRWatchAdapter.java) |
| Base Adapter | `FossilWatchAdapter.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil/FossilWatchAdapter.java) |
| Device Discovery | `QHybridCoordinator.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/devices/qhybrid/QHybridCoordinator.java) |
| File Handles | `FileHandle.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FileHandle.java) |
| Authentication | `VerifyPrivateKeyRequest.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/authentication/VerifyPrivateKeyRequest.java) |
| Notifications | `PlayNotificationRequest.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/notification/PlayNotificationRequest.java) |
| Configuration | `ConfigurationPutRequest.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/configuration/ConfigurationPutRequest.java) |
| File Upload | `FilePutRawRequest.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FilePutRawRequest.java) |
| App Writer | `FossilAppWriter.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/util/protobuf/FossilAppWriter.java) |
| Activity Parser | `ActivityFileParser.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/parser/ActivityFileParser.java) |
| File Lookup | `FileLookupRequest.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FileLookupRequest.java) |
| Encrypted Get | `FileEncryptedGetRequest.java` | [View](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/file/FileEncryptedGetRequest.java) |

---

## 9. Activity Data Fetch Protocol

Activity data (steps, heart rate, sleep, SpO2, workouts) is stored in an encrypted file on the watch.

### Fetch Flow Overview

**Source:** [FossilHRWatchAdapter.java#L1160-L1200](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil_hr/FossilHRWatchAdapter.java#L1160-L1200)

1. **File Lookup** - Get dynamic file handle for activity file
2. **Encrypted File Get** - Fetch encrypted data using CTR mode decryption
3. **Parse** - Decode binary activity file format

### Step 1: File Lookup Request

**Source:** [FileLookupRequest.java#L26-L60](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil/file/FileLookupRequest.java#L26-L60)

**Characteristic:** `3dda0003`

```
Byte 0:     0x02 (file lookup command)
Bytes 1-2:  File handle (little-endian, 0x0001 for activity)
```

**Response:**

```
Byte 0:     Response type (0x02 = lookup response)
Bytes 1-2:  Original file handle requested
Bytes 3-4:  Dynamic handle (use this for actual fetch)
```

### Step 2: Encrypted File Get Request

**Source:** [FileEncryptedGetRequest.java#L36-L85](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/file/FileEncryptedGetRequest.java#L36-L85)

**Characteristic:** `3dda0003`

```
Byte 0:     0x01 (file get command)
Byte 1:     Minor handle (from lookup response)
Byte 2:     Major handle (from lookup response)
Bytes 3-6:  Start offset (typically 0x00000000)
Bytes 7-10: End offset (0xFFFFFFFF for full file)
```

### AES-CTR Decryption for File Get

**Source:** [FileEncryptedGetRequest.java#L82-L140](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/requests/fossil_hr/file/FileEncryptedGetRequest.java#L82-L140)

Unlike authentication (CBC mode), file transfers use **AES-128 CTR mode**:

1. IV is constructed from phone and watch random numbers (established during auth)
2. First data packet contains the IV incrementor value (used to initialize counter)
3. Counter increments per 16-byte block

**IV Construction:**

```
IV[16] = {0}
IV[2-7]  = phoneRandomNumber[0-5]    // bytes 2-7 from phone random
IV[9-15] = watchRandomNumber[0-6]    // bytes 9-15 from watch random
```

**IV Incrementor Discovery:**

The first packet's first byte contains the IV incrementor (typically 0x1E-0x30). This value is added to IV byte 7 for each 16-byte block processed.

### Activity File Format (Version 22)

**Source:** [ActivityFileParser.java#L80-L320](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/parser/ActivityFileParser.java#L80-L320)

**File Header (52 bytes):**

```
Bytes 0-3:   File version (should be 0x16 = 22)
Bytes 4-7:   Header length (52 bytes)
Bytes 8-11:  Total sample count
Bytes 12-15: Start timestamp (Unix epoch seconds)
Byte 16:     Sample size (typically 4 bytes per sample)
Bytes 17-19: Reserved
Bytes 20-23: Unknown timestamp or offset
Bytes 24-27: Unknown (possibly end timestamp)
Bytes 28-31: Reserved or flags
Bytes 32-51: Additional metadata
```

**Sample Entry Types (packet type byte):**

| Type | Hex | Description | Data Format |
|------|-----|-------------|-------------|
| Main Activity | 0xCE | Steps, HR, calories | See below |
| Workout Summary | 0xE0 | Workout records | Variable length |
| SpO2 | 0xD6 | Blood oxygen readings | 4-7 bytes |
| Unknown | 0xE3 | Unknown data | Variable |

### Main Activity Sample (0xCE type)

**Source:** [ActivityFileParser.java#L207-L223](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/parser/ActivityFileParser.java#L207-L223)

Activity samples are parsed from variability bytes (`lower` and `higher`) and other attributes.

**Step Count Decoding:**

The step count encoding depends on the LSB (bit 0) of the `lower` variability byte:

1. **If bit 0 is SET (1):**
   - Steps are in bits 1-3 (mask `0x0E`)
   - `stepCount = (lower & 0x0E) >> 1`

2. **If bit 0 is UNSET (0):**
   - Steps are in bits 1-7 (mask `0xFE`)
   - `stepCount = (lower & 0xFE) >> 1`

**Note:** Previous documentation suggested a complex shift/merge with the second byte, but empirical testing confirms the simple masked right-shift is correct for this device generation.

**Heart Rate Quality Values:**

| Quality | Meaning |
|---------|---------|
| 0 | No measurement |
| 1 | Poor quality |
| 2 | Acceptable |
| 3+ | Good quality |

### Workout Summary (0xE0 type)

**Source:** [ActivityFileParser.java#L250-L280](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/parser/ActivityFileParser.java#L250-L280)

```
Bytes 0-3:   Start timestamp (Unix epoch)
Bytes 4-5:   Duration (seconds)
Byte 6:      Workout type
Bytes 7-8:   Calories burned
Bytes 9-10:  Average heart rate
Bytes 11-12: Step count
...additional fields vary by workout type
```

### SpO2 Sample (0xD6 type)

```
Bytes 0-3:   Timestamp
Byte 4:      SpO2 percentage (0-100)
Byte 5:      Quality indicator
Byte 6:      Confidence score (optional)
```

### Deleting Activity Data After Fetch

**Source:** [FossilHRWatchAdapter.java#L1195-L1198](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/adapter/fossil_hr/FossilHRWatchAdapter.java#L1195-L1198)

After successfully parsing activity data, send a `FileDeleteRequest` to clear the data from the watch:

```
Byte 0:     0x05 (file delete command)
Bytes 1-2:  File handle (little-endian, 0x0001 for activity)
```
