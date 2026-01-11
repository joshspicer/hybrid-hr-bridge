# iOS Notification Architecture for Fossil Hybrid HR

## ⚠️ Current Status: Notifications Not Working (Reason Unknown)

After extensive testing, we were unable to get notifications to display on the watch. We don't know why. This document describes what we tried and what we observed. See [NOTIFICATION_RESEARCH.md](NOTIFICATION_RESEARCH.md) for detailed protocol research.

## What We Know For Certain

1. **iOS shows "Share System Notifications" toggle** for the watch in Bluetooth settings
2. **`peripheral.ancsAuthorized` returns `true`** after enabling the toggle
3. **Notifications don't appear on the watch** despite the above
4. **The proprietary protocol data is accepted** - watch returns success code `0x05` ("file written/applied")
5. **Notifications still don't display** even when proprietary protocol succeeds

## What We Don't Know

- Whether the watch actually supports ANCS (we haven't proven or disproven this)
- Why enabling "Share System Notifications" doesn't result in notifications appearing
- Why the proprietary Fossil protocol succeeds but doesn't display anything
- What Gadgetbridge does differently on Android that makes it work

## Our Theories (Unproven)

### Theory 1: Watch Doesn't Implement ANCS Client
The watch might not actually implement an ANCS client, meaning iOS's "Share System Notifications" toggle does nothing useful. The toggle might appear for any bonded BLE device regardless of actual ANCS support.

**Evidence for:** Watch doesn't expose ANCS service UUID when we scan its services.
**Evidence against:** Why would iOS show the toggle if it doesn't work?

### Theory 2: ANCS Works But Needs Additional Setup
ANCS might be supported but require additional configuration on the watch side (via the proprietary protocol) that we haven't discovered.

**Evidence for:** Gadgetbridge sends notification filter configuration before ANCS would work.
**Evidence against:** We tried uploading filters and they were accepted, but still nothing displayed.

### Theory 3: Missing Watchface/Widget
The watch might require a specific watchface with a notification widget enabled for notifications to display.

**Evidence for:** Gadgetbridge code checks `isNotificationWidgetVisible()`.
**Evidence against:** We haven't tested this - it's speculation.

### Theory 4: Icon Dependencies
The watch might require notification icons to be uploaded before displaying notifications. Our icon uploads consistently fail with error code `0x02` ("OPERATION_IN_PROGRESS").

**Evidence for:** Gadgetbridge uploads icons as part of notification setup.
**Evidence against:** Filters uploaded successfully without icons, theoretically should work.

## What We Can Observe

### ANCS Authorization Status

iOS does report ANCS authorization via CoreBluetooth:

```swift
// CBPeripheral property (iOS 13+)
let authorized = peripheral.ancsAuthorized

// CBCentralManagerDelegate callback
func centralManager(_ central: CBCentralManager, 
                    didUpdateANCSAuthorizationFor peripheral: CBPeripheral)
```

Our app monitors this. It reports `true` after enabling "Share System Notifications", but notifications still don't appear. This could mean:
- ANCS isn't actually supported despite the property being true
- ANCS is supported but something else is missing
- We have a bug somewhere

### The Toggle Exists

1. Go to **iOS Settings → Bluetooth**
2. Tap the **(i)** next to your watch
3. **"Share System Notifications"** toggle is present

Enabling this alone doesn't make notifications work in our testing.

## What Our App Actually Provides (Working Features)

These features DO work:
- ✅ Device discovery and connection
- ✅ Secret key authentication
- ✅ Battery status monitoring
- ✅ Activity data sync (steps, heart rate, calories)
- ✅ Time synchronization
- ✅ Watch app installation (.wapp files)
- ✅ Debug logging

This does NOT work (yet):
- ❌ Notifications (ANCS or proprietary) - reason unknown

## Platform Comparison

| Feature | iOS | Android (Gadgetbridge) |
|---------|-----|------------------------|
| System notifications | ❌ Not working (unknown why) | ✅ Works |
| Proprietary protocol | Data accepted, not displayed | ✅ Works |

## Next Steps for Investigation

1. **Sniff Gadgetbridge traffic** - Capture working Android → watch communication with Wireshark
2. **Test with notification widget** - Try a watchface that explicitly has notification support
3. **Compare firmware versions** - Check if behavior varies by firmware
4. **Try different watch models** - Test on Fossil HR vs Skagen Hybrid
5. **Deep dive ANCS** - Investigate if we need to do something on the app side for ANCS to work

## References

- [NOTIFICATION_RESEARCH.md](NOTIFICATION_RESEARCH.md) - Detailed protocol documentation
- [ANCS Specification](https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/) - Apple's official docs
- [Gadgetbridge Fossil HR Wiki](https://codeberg.org/Freeyourgadget/Gadgetbridge/wiki/Fossil-Hybrid-HR) - Works on Android

## Conclusion

We don't have a working solution for notifications. The watch accepts all our protocol messages with success codes, but nothing displays. We have theories but haven't proven or disproven any of them. Further investigation needed.
