# Fossil Hybrid HR Notification Research

## 🎉 UPDATE: Implementation Complete (January 2026)

**The iOS notification system has been fully implemented!** See [IOS_NOTIFICATION_IMPLEMENTATION.md](./IOS_NOTIFICATION_IMPLEMENTATION.md) for complete implementation details.

### What Was Implemented

1. ✅ **iOS Notification Interception** - UserNotifications framework integration
2. ✅ **Notification Protocol** - RLE icon encoding, filter configuration, payload building
3. ✅ **File Transfer Integration** - Upload icons/filters, send notifications

### Implementation Status

- **Code**: Complete and ready for testing
- **Protocol**: Follows Gadgetbridge specification exactly
- **Testing**: Requires physical iPhone + watch (cannot test in simulator)

### Key Discovery from Implementation

The implementation revealed a **critical requirement** from Gadgetbridge source code:

**Notifications require a watchface with a `LAST_NOTIFICATION` widget** to display. This is checked in `FossilHRWatchAdapter.java:1379-1386` before sending notifications.

This explains why previous attempts failed - the watch accepts the data but won't display without the widget.

---

## Original Research (Historical)

This document summarizes extensive research into implementing iOS notification delivery on Fossil/Skagen Hybrid HR watches. **This feature was not successfully implemented** in the original research attempt - the watch accepted all notification data but never displayed it on screen.

**Note**: The implementation described below has since been completed - see above for current status.

## TL;DR

- **ANCS (Apple Notification Center Service)** does NOT work because the Fossil HR watch firmware doesn't implement an ANCS client
- **Proprietary Fossil Protocol** was implemented based on Gadgetbridge - the watch accepts all data (response code 0x05 = "file written/applied") but never displays notifications
- **Root cause unknown** - the protocol appears correct per Gadgetbridge source, but something is missing for iOS

## Key Discovery: Fossil HR Does NOT Use ANCS

The Fossil Hybrid HR watch does **not** have a native ANCS client. When connected via Bluetooth:

```
[BLE] Watch does not expose ANCS service - this is normal
[BLE] Service: 3DDA0001-957F-7D4A-34A6-74696673696D - Fossil Proprietary Service
[BLE] Service: Heart Rate  
[BLE] Service: 108B5094-4C03-E51C-555E-105D1A1155F0 (Unknown)
```

The watch exposes its **proprietary service** (`3dda0001-...`) but no standard ANCS service (`7905F431-B5CE-4E99-A40F-4B1E122D00D0`).

### Why Gadgetbridge (Android) Works

Gadgetbridge on Android manually intercepts phone notifications and forwards them to the watch using the proprietary Fossil protocol. There is no ANCS on Android, so this approach works.

On iOS, the assumption was that enabling "Share System Notifications" would make ANCS handle everything. This is incorrect for Fossil HR watches - they require the same manual forwarding as Android.

## Proprietary Notification Protocol

### File Handles

| Handle | Name | Purpose |
|--------|------|---------|
| `0x0900` | NOTIFICATION_PLAY | Send notifications to display |
| `0x0C00` | NOTIFICATION_FILTER | Configure which apps show notifications |
| `0x0701` | ASSET_NOTIFICATION_IMAGES | Upload custom notification icons |

### Notification Payload Format

From `PlayNotificationRequest.java`:

```
[totalLength:2][lengthHeader=0x0A:1][type:1][flags:1][uidLength=4:1]
[pkgCrcLength=4:1][titleLen:1][senderLen:1][msgLen:1][messageId:4]
[packageCRC:4][title\0][sender\0][message\0]
```

- **totalLength**: Little-endian 16-bit payload size
- **lengthHeader**: Always `0x0A` (10)
- **type**: `1`=incomingCall, `2`=text, `3`=notification, `7`=dismissNotification
- **flags**: `0x02`=standard notification, `0x18`=incoming call, `0x38`=call with quick reply
- **messageId**: Unique notification ID (4 bytes LE)
- **packageCRC**: CRC32 of app identifier, used to match notification filters

### Notification Types

| Value | Type | Use Case |
|-------|------|----------|
| 1 | INCOMING_CALL | Phone calls - triggers vibration |
| 2 | TEXT | SMS/text messages |
| 3 | NOTIFICATION | Generic app notifications |
| 7 | DISMISS_NOTIFICATION | Remove notification from watch |

### Filter Configuration Format

From `NotificationFilterPutHRRequest.java`:

```
[entryLength:2]
  [0x04][0x04][packageCRC:4]     // Package name CRC
  [0x80][0x01][0x00]             // Group ID (always 0)
  [0xC1][0x01][0xFF]             // Priority (0xFF = highest)
  [0x82][len][flags][nameLen][iconName\0]  // Icon reference (optional)
```

For call notifications, a **multi-icon format** is required:
```
[0x82][totalLen]
  [0x02][0x00][len]icIncomingCall.icon\0   // Call start
  [0x40][0x00][len]icMissedCall.icon\0     // Missed call
  [0xBD][0x00][len]icIncomingCall.icon\0   // Call end
```

### CRC Values

| Package | CRC32 (LE) | Use |
|---------|------------|-----|
| "generic" | `0x964FA1D3` | Default fallback |
| "call" | `0xB7590080` | **Hardcoded** call CRC |

The call CRC is NOT computed - it's hardcoded in `PlayCallNotificationRequest.java`:
```java
ByteBuffer.wrap(new byte[]{(byte) 0x80, (byte) 0x00, (byte) 0x59, (byte) 0xB7})
    .order(ByteOrder.LITTLE_ENDIAN).getInt()
```

## What Was Implemented

### 1. NotificationConfiguration.swift
- Built notification filter files matching Gadgetbridge format
- Implemented RLE-encoded icon generation (24×24, 2-bit grayscale + 2-bit alpha)
- Created multi-icon call notification filter

### 2. FileTransferManager Extensions
- `sendNotification()` - Send text/generic notifications
- `sendCallNotification()` - Send incoming call notifications with correct flags
- `configureNotifications()` - Upload notification filters
- `uploadNotificationIcons()` - Upload custom icons (failed with code 2)

### 3. RequestBuilder.buildNotification()
- Correct payload format per Gadgetbridge
- Null-terminated strings
- Little-endian byte order

## Test Results

### What Worked ✅
- Filter upload: Code `0x05` (file written/applied)
- Notification upload: Code `0x05` (file written/applied)
- All data accepted by watch

### What Failed ❌
- Icon upload: Code `0x02` (OPERATION_IN_PROGRESS) - consistently rejected
- **Notifications never appear on watch display**

### Log Evidence

```
[NotificationConfig] Filters file size: 97 bytes
[FileTransfer] Transfer complete with code 0x05 (file written/applied)
[NotificationConfig] ✅ Notification filters uploaded successfully

[Notification] Type: incomingCall, flags: 0x18
[Notification] Display: 'Mom'
[Notification] CRC: 0xB7590080, msgID: 1
[FileTransfer] Transfer complete with code 0x05 (file written/applied)
[Notification] ✅ Call notification sent successfully
```

The watch accepts everything but displays nothing.

## Possible Missing Pieces

1. **Watchface/Widget Requirement**: Gadgetbridge may require a specific watchface with notification widget. See `isNotificationWidgetVisible()` in `FossilHRWatchAdapter.java`.

2. **Icon Dependencies**: Filters reference icons like `icIncomingCall.icon` and `general_white.bin`. These may need to be uploaded, but icon upload fails on our watch.

3. **Initialization Sequence**: There may be additional setup required after authentication that we haven't discovered.

4. **Firmware Differences**: Our Skagen Gen 6 Hybrid may have different firmware behavior than watches tested with Gadgetbridge.

5. **iOS vs Android Timing**: Android may send notifications at different points in the connection lifecycle.

## Gadgetbridge Source References

All implementation was based on these files:

- **PlayNotificationRequest.java**: Base notification payload format
  - https://codeberg.org/Freeyourgadget/Gadgetbridge/.../PlayNotificationRequest.java

- **PlayCallNotificationRequest.java**: Call notification specifics
  - https://codeberg.org/Freeyourgadget/Gadgetbridge/.../PlayCallNotificationRequest.java

- **PlayTextNotificationRequest.java**: Text notification handling
  - https://codeberg.org/Freeyourgadget/Gadgetbridge/.../PlayTextNotificationRequest.java

- **NotificationFilterPutHRRequest.java**: Filter configuration format
  - https://codeberg.org/Freeyourgadget/Gadgetbridge/.../NotificationFilterPutHRRequest.java

- **NotificationImagePutRequest.java**: Icon upload format
  - https://codeberg.org/Freeyourgadget/Gadgetbridge/.../NotificationImagePutRequest.java

- **FossilHRWatchAdapter.java**: `setNotificationConfigurations()` and `playRawNotification()`
  - Lines 600-650: Icon + filter upload sequence
  - Lines 1388-1433: Notification sending logic

## Future Investigation Ideas

1. **Sniff Gadgetbridge Traffic**: Use Wireshark/btsnoop to capture working Gadgetbridge → watch communication
2. **Compare Firmware Versions**: Check if older/newer firmware behaves differently
3. **Try Different Watch Models**: Test on Fossil HR vs Skagen Hybrid
4. **Custom Watchface**: Build watchface with notification widget using Fossil HR SDK
5. **Check iOS Notification Entitlements**: May need specific iOS app capabilities

## Conclusion

The Fossil Hybrid HR notification protocol was reverse-engineered from Gadgetbridge and implemented correctly to the best of our analysis. The watch accepts all protocol commands with success codes, but never displays notifications. This suggests either:

1. Missing prerequisite setup step
2. iOS-specific behavior not documented in Gadgetbridge
3. Hardware/firmware differences from tested devices

Until further research, **notifications on iOS remain non-functional** despite correct protocol implementation.
