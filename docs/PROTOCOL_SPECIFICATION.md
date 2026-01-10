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

### Main Activity Sample (0xCE type, 4 bytes per sample)

**Source:** [ActivityFileParser.java#L150-L220](https://codeberg.org/Freeyourgadget/Gadgetbridge/src/branch/master/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/parser/ActivityFileParser.java#L150-L220)

Each sample represents **1 minute** of activity data:

```
Byte 0: variability[0] - encodes step count bits and variability
Byte 1: variability[1] - encodes heart rate quality and variability
Byte 2: heartRate - raw heart rate value
Byte 3: caloriesBurned - calorie count for this minute
```

**Variability Byte Decoding:**

```
// Byte 0 bits:
stepCount = (variability[0] & 0x1F) << 2    // bits 0-4 shifted left 2
isActive = (variability[0] & 0x20) != 0     // bit 5
wornMin = (variability[0] & 0xC0) >> 6      // bits 6-7

// Byte 1 bits:
stepCount |= (variability[1] & 0x03)        // bits 0-1 added to step count
hrQuality = (variability[1] & 0x1C) >> 2    // bits 2-4 (heart rate quality)
var = (variability[1] & 0xE0) >> 5          // bits 5-7 (HRV data)

// Combined step count:
finalStepCount = ((variability[0] & 0x1F) << 2) | (variability[1] & 0x03)
```

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
