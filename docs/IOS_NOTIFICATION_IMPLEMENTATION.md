# iOS Notification Implementation Guide

## Overview

This document describes the complete implementation of iOS notification forwarding to Fossil/Skagen Hybrid HR watches. The implementation is based on extensive research of the Gadgetbridge Android app's notification handling and follows the proprietary Fossil protocol exactly.

## Implementation Summary

The notification system consists of three main components:

1. **NotificationService** - Intercepts iOS notifications using UserNotifications framework
2. **NotificationConfiguration** - Builds notification filters and RLE-encoded icons
3. **FileTransferManager** - Uploads icons/filters and sends notification payloads to watch

## Architecture

```
iOS Notification
       ↓
NotificationService (UNUserNotificationCenterDelegate)
       ↓
NotificationConfiguration (Build filters + icons)
       ↓
FileTransferManager (BLE file transfers)
       ↓
Watch Display (if watchface has notification widget)
```

## Key Components

### 1. NotificationService.swift

Handles iOS notification interception and forwarding:

- Requests notification permissions from user
- Implements `UNUserNotificationCenterDelegate` to capture notifications
- Manages notification state (count, last notification)
- Forwards notifications to watch via `FileTransferManager`

**Key Methods:**
- `requestNotificationPermissions()` - Request iOS notification access
- `configureWatchNotifications()` - Upload icons and filters to watch
- `forwardNotificationToWatch()` - Send notification payload to watch
- `sendTestNotification()` - Send a test notification for debugging

### 2. NotificationConfiguration.swift

Implements the Fossil notification protocol:

**NotificationConfiguration:**
- Builds notification filter files (file handle 0x0C00)
- Calculates package CRC32 values
- Supports multi-icon format for call notifications
- Standard configurations: `generic`, `call`

**NotificationIcon:**
- Encodes icons to 2-bit grayscale + 2-bit alpha
- RLE compression for efficient transfer
- Maximum 24x24 pixels
- Builds icon files (file handle 0x0701)
- Standard icons: `general_white.bin`, `icIncomingCall.icon`, `icMissedCall.icon`, `icMessage.icon`

**Source References:**
- `NotificationHRConfiguration.java` - Filter configuration
- `NotificationImage.java` - Icon format
- `NotificationFilterPutHRRequest.java` - Filter file structure
- `ImageConverter.java` - Image encoding
- `RLEEncoder.java` - RLE compression

### 3. FileTransferManager Extensions

Added notification-specific file transfer methods:

- `uploadNotificationIcons()` - Upload icons to file handle 0x0701
- `uploadNotificationFilters()` - Upload filters to file handle 0x0C00
- `sendNotification()` - Send notification to file handle 0x0900

### 4. RequestBuilder Extensions

Added notification payload building:

- `buildNotificationPayload()` - Build notification data per Gadgetbridge spec
- Supports notification types: incomingCall (1), text (2), notification (3)
- Null-terminated strings for title, sender, message
- Little-endian byte order

**Payload Structure:**
```
[totalLength:2][lengthHeader=0x0A:1][type:1][flags:1][uidLength=4:1]
[pkgCrcLength=4:1][titleLen:1][senderLen:1][msgLen:1][messageId:4]
[packageCRC:4][title\0][sender\0][message\0]
```

### 5. NotificationSettingsView.swift

User interface for notification management:

- Display permission status (iOS notifications + ANCS)
- Request notification permissions button
- Send test notification button
- Configure watch button
- Notification statistics display
- Implementation phase status

## Usage

### Setup (One-time)

1. **Request iOS Notification Permissions:**
```swift
await watchManager.requestNotificationPermissions()
```

2. **Enable ANCS in iOS Settings:**
- Go to Settings > Bluetooth > [Watch Name] > (i)
- Enable "Share System Notifications"

3. **Configure Watch (after authentication):**
```swift
await watchManager.configureWatchNotifications()
```

This uploads:
- Standard notification icons (4 icons, ~500 bytes)
- Notification filters (generic + call, ~97 bytes)

### Automatic Notification Forwarding

Once configured, `NotificationService` automatically:
1. Captures iOS notifications via `UNUserNotificationCenterDelegate`
2. Extracts notification data (title, body, app identifier)
3. Builds notification payload per Fossil protocol
4. Sends to watch via file handle 0x0900

### Manual Test

```swift
await watchManager.sendTestNotification()
```

## Protocol Details

### File Handles

| Handle | Name | Purpose |
|--------|------|---------|
| 0x0701 | ASSET_NOTIFICATION_IMAGES | Upload notification icons |
| 0x0C00 | NOTIFICATION_FILTER | Configure notification routing |
| 0x0900 | NOTIFICATION_PLAY | Send notifications to display |

### Notification Types

| Value | Type | Flags | Use Case |
|-------|------|-------|----------|
| 1 | INCOMING_CALL | 0x18 | Phone calls |
| 2 | TEXT | 0x02 | SMS/Messages |
| 3 | NOTIFICATION | 0x02 | Generic app notifications |
| 7 | DISMISS_NOTIFICATION | - | Remove notification from watch |

### Icon Format

- **Size**: Maximum 24x24 pixels
- **Color Depth**: 2-bit grayscale (4 shades)
- **Alpha**: 2-bit alpha (4 levels)
- **Compression**: RLE encoded
- **Format**: See `docs/NOTIFICATION_ICONS.md` for detailed specification

### Filter Format

Each filter entry contains:
- Package CRC (4 bytes) - Identifies the app
- Group ID (always 0)
- Priority (0xFF = highest)
- Icon name reference (null-terminated string)

Call notifications use a multi-icon format with 3 icon references:
- Call start icon (`icIncomingCall.icon`)
- Missed call icon (`icMissedCall.icon`)
- Call end icon (`icIncomingCall.icon`)

## Critical Discovery: Notification Widget Requirement

**From Gadgetbridge research (FossilHRWatchAdapter.java:1379-1386):**

```java
private boolean isNotificationWidgetVisible() {
    for (Widget widget : widgets) {
        if (widget.getWidgetType() == Widget.WidgetType.LAST_NOTIFICATION) {
            return true;
        }
    }
    return false;
}
```

Gadgetbridge checks if the current watchface has a `LAST_NOTIFICATION` widget before sending notifications. This suggests:

1. **Notifications require a specific watchface widget to display**
2. The watch may accept notification data even without the widget
3. Default watchfaces may not have notification support

### Implications

If notifications don't appear on the watch:
1. Check if the current watchface has a notification widget
2. Try installing a watchface with notification support
3. Use Gadgetbridge's watchface designer to add notification widget
4. Refer to Fossil HR SDK documentation for watchface development

## Testing Checklist

- [ ] iOS notification permissions granted
- [ ] ANCS authorized in iOS Bluetooth settings
- [ ] Watch connected and authenticated
- [ ] Notification icons uploaded successfully (no error code 0x02)
- [ ] Notification filters uploaded successfully (response code 0x05)
- [ ] Test notification sent successfully (response code 0x05)
- [ ] Notification appears on watch display
- [ ] Real iOS notifications forwarded automatically
- [ ] Check debug logs for any errors

## Known Issues & Limitations

### Previous Implementation Attempts

From `docs/NOTIFICATION_RESEARCH.md`:
- Watch accepts all protocol data (response code 0x05)
- Icons may fail to upload (error code 0x02 observed)
- **Notifications never displayed** despite correct protocol

### Possible Causes

1. **Missing watchface widget** (most likely based on Gadgetbridge code)
2. Icon dependencies not satisfied
3. Additional initialization step required
4. Firmware differences between watch models
5. iOS-specific timing or permission issues

### Debugging Tips

1. **Check logs:** Use Debug Logs screen to export full log
2. **Verify response codes:**
   - 0x05 = Success (file written/applied)
   - 0x02 = Operation in progress (may indicate rejection)
3. **Test with Gadgetbridge:** Compare behavior on Android
4. **Try different watchfaces:** Some may have notification support
5. **Check firmware version:** Newer firmware may behave differently

## Source Code References

All implementation based on Gadgetbridge source:
- [FossilHRWatchAdapter.java](https://codeberg.org/Freeyourgadget/Gadgetbridge/.../FossilHRWatchAdapter.java) - Main notification logic
- [NotificationHRConfiguration.java](https://codeberg.org/Freeyourgadget/Gadgetbridge/.../NotificationHRConfiguration.java) - Filter config
- [NotificationImage.java](https://codeberg.org/Freeyourgadget/Gadgetbridge/.../NotificationImage.java) - Icon format
- [PlayNotificationRequest.java](https://codeberg.org/Freeyourgadget/Gadgetbridge/.../PlayNotificationRequest.java) - Notification payloads
- [ImageConverter.java](https://codeberg.org/Freeyourgadget/Gadgetbridge/.../ImageConverter.java) - Image encoding
- [RLEEncoder.java](https://codeberg.org/Freeyourgadget/Gadgetbridge/.../RLEEncoder.java) - RLE compression

## Next Steps

1. **Deploy to physical iPhone** (simulator cannot test Bluetooth)
2. **Connect to watch** and authenticate
3. **Configure notifications** via settings UI
4. **Send test notification** and check watch display
5. **Verify real notifications** are forwarded
6. **Document results** in `NOTIFICATION_RESEARCH.md`

If notifications still don't display:
- Research watchface widget requirements
- Attempt to install watchface with notification support
- Compare with Gadgetbridge behavior on Android
- Consider firmware update if available

## Conclusion

This implementation completes all three phases of iOS notification support:
1. ✅ iOS notification interception
2. ✅ Notification protocol implementation
3. ✅ File transfer integration

The code follows Gadgetbridge's implementation exactly and should work if:
- The watch firmware supports notifications
- The current watchface has a notification widget
- All prerequisites are satisfied (permissions, authentication, etc.)

Further testing on physical hardware is required to verify functionality and identify any remaining issues.
