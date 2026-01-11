# Notification Icon Format Specification for Fossil Hybrid HR

This document specifies the exact binary format for notification icons on Fossil Hybrid HR watches, based on reverse-engineering of the Gadgetbridge implementation.

## Overview

Notification icons on the Fossil Hybrid HR are:
- Maximum **24x24 pixels**
- **2-bit grayscale with 2-bit alpha** (4 levels of gray + 4 levels of transparency)
- **RLE encoded** (Run-Length Encoding) for efficiency
- Uploaded to file handle **0x0701** (`ASSET_NOTIFICATION_IMAGES`)
- Associated with apps via notification filters on file handle **0x0C00** (`NOTIFICATION_FILTER`)

---

## 1. Icon Image Binary Format

### 1.1 RLE Image Structure

Icons are RLE-encoded 2-bit grayscale images with the following structure:

```
[height: 1 byte]
[width: 1 byte]
[RLE data: variable length]
[terminator: 0xFF 0xFF]
```

### 1.2 Pixel Format (2-bit grayscale + 2-bit alpha)

Each pixel is encoded as a single byte before RLE compression:

```
Bits 0-1: Grayscale value (0-3)
  - 0b00 = Black (0x00)
  - 0b01 = Dark gray (~0x55)
  - 0b10 = Light gray (~0xAA)
  - 0b11 = White (0xFF)

Bits 2-3: Alpha/transparency (inverted)
  - 0b00 = Fully opaque (alpha 255)
  - 0b11 = Fully transparent (alpha 0)
```

**Encoding formula from RGB+Alpha:**
```swift
// Convert RGB to grayscale
let gray = (red + green + blue) / 3
let grayValue = (gray >> 6) & 0b11  // Top 2 bits -> 0-3

// Invert alpha for encoding
let alphaValue = (~alpha >> 4) & 0b1100  // Inverted, shifted

let pixel = grayValue | alphaValue  // Combine into single byte
```

Source: `ImageConverter.java#L27-L35`

### 1.3 RLE Encoding Algorithm

Simple run-length encoding:
- For each run of identical pixels
- Write: `[count: 1 byte] [pixel_value: 1 byte]`
- Maximum run length is 255

```swift
func rleEncode(_ pixels: [UInt8]) -> Data {
    var result = Data()
    var lastByte = pixels[0]
    var count: UInt8 = 1
    
    for i in 1..<pixels.count {
        let currentByte = pixels[i]
        if currentByte == lastByte && count < 255 {
            count += 1
        } else {
            result.append(count)
            result.append(lastByte)
            lastByte = currentByte
            count = 1
        }
    }
    // Write final run
    result.append(count)
    result.append(lastByte)
    return result
}
```

Source: `RLEEncoder.java#L22-L44`

---

## 2. Notification Image File Format (0x0701)

When uploading multiple notification icons, they're concatenated with this per-icon wrapper:

```
┌─────────────────────────────────────────────────────────────────┐
│ Offset │ Size   │ Field           │ Description                 │
├────────┼────────┼─────────────────┼─────────────────────────────┤
│ 0      │ 2      │ entry_size      │ Total size of this entry    │
│        │        │                 │ (little-endian)             │
├────────┼────────┼─────────────────┼─────────────────────────────┤
│ 2      │ varies │ filename        │ Null-terminated ASCII       │
│        │        │                 │ e.g., "com.app.icon\0"      │
├────────┼────────┼─────────────────┼─────────────────────────────┤
│ varies │ 1      │ width           │ Icon width in pixels (≤24)  │
├────────┼────────┼─────────────────┼─────────────────────────────┤
│ varies │ 1      │ height          │ Icon height in pixels (≤24) │
├────────┼────────┼─────────────────┼─────────────────────────────┤
│ varies │ varies │ image_data      │ RLE-encoded image data      │
│        │        │                 │ (WITHOUT height/width header│
│        │        │                 │ - those are in wrapper)     │
├────────┼────────┼─────────────────┼─────────────────────────────┤
│ varies │ 2      │ terminator      │ 0xFF 0xFF                   │
└─────────────────────────────────────────────────────────────────┘

entry_size = filename.length + 1 (null) + 1 (width) + 1 (height) 
           + image_data.length + 2 (terminator)
```

Source: `NotificationImagePutRequest.java#L42-L56`

### Example Binary (24x24 white square icon named "test.icon"):

```
Raw pixels (before RLE): 576 bytes of 0x03 (white, opaque)
RLE encoded: 0xFF 0x03, 0xFF 0x03, 0x42 0x03 (255+255+66 = 576)

File structure:
0x00-0x01: 0x14 0x00  // entry_size = 20 (little-endian)
0x02-0x0B: "test.icon\0"  // filename (10 bytes)
0x0C:      0x18       // width = 24
0x0D:      0x18       // height = 24
0x0E-0x13: 0xFF 0x03 0xFF 0x03 0x42 0x03  // RLE data
0x14-0x15: 0xFF 0xFF  // terminator
```

---

## 3. Standard Icon Filenames

### 3.1 Standard Icons Uploaded by Gadgetbridge

| Filename              | Purpose                    | Source Icon              |
|-----------------------|----------------------------|--------------------------|
| `icIncomingCall.icon` | Incoming call notification | ic_phone_outline         |
| `icMissedCall.icon`   | Missed call notification   | ic_phone_missed_outline  |
| `icMessage.icon`      | SMS/Message notification   | ic_message_outline       |
| `general_white.bin`   | Generic/fallback icon      | ic_alert_circle_outline  |

### 3.2 App-Specific Icon Naming Convention

Gadgetbridge shortens package names for icon filenames:
```
com.whatsapp -> whatsapp.icon
com.google.android.gm -> gm.icon
```

Source: `FossilHRWatchAdapter.java#L614`

---

## 4. Built-in Watch Icons (No Upload Required!)

The Fossil HR firmware includes **built-in icons** that can be referenced by name without uploading. These are usable in layouts and notifications:

| Icon Name      | Description               |
|----------------|---------------------------|
| `icTimer`      | Timer icon                |
| `icStopwatch`  | Stopwatch icon            |
| `icAdd`        | Add/Plus icon             |
| `icAlert`      | Alert/Warning icon        |
| `icClose`      | Close/X icon              |
| `icCheck`      | Checkmark icon            |
| `icHome`       | Home icon                 |
| `icSettings`   | Settings gear icon        |
| `icMusic`      | Music note icon           |
| `icWeather`    | Weather icon              |

**Usage in notifications** (from SDK documentation):
```javascript
response.i = [{
    'type': 'urgent_notification',
    'info': {
        'title': 'Timer Done',
        'app_name': 'myapp',
        'icon_name': 'icTimer',  // Built-in icon, no upload needed!
        // ...
    }
}]
```

Source: `DOCUMENTATION.md#L333-L366`, `app.js#L73-L103`

---

## 5. Notification Filter Configuration (0x0C00)

To associate an app/package with an icon, use the notification filter:

### 5.1 Filter Entry Structure

```
┌─────────────────────────────────────────────────────────────────┐
│ Offset │ Size   │ Field              │ Description              │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 0      │ 2      │ entry_size         │ Little-endian size       │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 2      │ 6      │ package_crc        │ 0x04, 0x04, [4-byte CRC] │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 8      │ 3      │ group_id           │ 0x80, 0x01, 0x00         │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 11     │ 3      │ priority           │ 0xC1, 0x01, 0xFF         │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 14     │ varies │ icon_config        │ Icon filename reference  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Icon Config Sub-structure

```
0x82                      // PacketID.ICON
(iconName.length + 4)     // total icon config length
0xFF                      // mask (0xFF = all notification types)
0x00                      // reserved
(iconName.length + 1)     // icon name length with null
iconName.bytes            // ASCII icon filename
0x00                      // null terminator
```

### 5.3 CRC32 Calculation

The package name CRC is calculated using standard CRC32:
```swift
import zlib

let packageCrc = crc32(0, packageName.utf8)
// Store as 4 bytes little-endian
```

---

## 6. Playing Notifications (0x0900)

Notifications are played using file handle `0x0900` (`NOTIFICATION_PLAY`):

```
┌─────────────────────────────────────────────────────────────────┐
│ Offset │ Size   │ Field              │ Description              │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 0      │ 2      │ total_length       │ Little-endian            │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 2      │ 1      │ length_buffer_size │ Always 0x0A (10)         │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 3      │ 1      │ notification_type  │ 0x03 = notification      │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 4      │ 1      │ flags              │ 0x02 = normal            │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 5      │ 1      │ uid_length         │ Always 0x04              │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 6      │ 1      │ crc_length         │ Always 0x04              │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 7      │ 1      │ title_length       │ Length of title+null     │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 8      │ 1      │ sender_length      │ Length of sender+null    │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 9      │ 1      │ message_length     │ Length of message+null   │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 10     │ 4      │ message_id         │ Unique notification ID   │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 14     │ 4      │ package_crc        │ CRC32 of package name    │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ 18     │ varies │ title              │ Null-terminated UTF-8    │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ varies │ varies │ sender             │ Null-terminated UTF-8    │
├────────┼────────┼────────────────────┼──────────────────────────┤
│ varies │ varies │ message            │ Null-terminated UTF-8    │
└─────────────────────────────────────────────────────────────────┘
```

**The icon is NOT embedded in the notification!** The watch looks up the icon via:
1. The `package_crc` field matches against notification filter entries
2. The matching filter entry specifies which icon filename to display
3. If no match, the "generic" filter uses `general_white.bin`

Source: `PlayNotificationRequest.java#L27-L74`

---

## 7. Alternative: Custom Apps Can Play Notifications with Built-in Icons

If implementing custom watch apps (via JavaScript), notifications can reference built-in icons directly without pre-uploading:

```javascript
response.i = [{
    'type': 'urgent_notification',
    'info': {
        'title': title_string,
        'app_name': package_name,
        'icon_name': 'icTimer',  // Built-in system icon
        'Re': 60,                // Timeout in seconds
        'vibe': {
            'type': 'timer',
            'Te': 1500,
            'Ie': 60000
        },
        'exit_event': { 'type': 'dismiss' },
        'actions': [
            { 'Ke': 'Dismiss', 'event': { 'type': 'dismiss' } }
        ]
    }
}]
```

---

## 8. Complete Swift Implementation Example

```swift
import Foundation
import zlib

struct NotificationIcon {
    static let MAX_WIDTH = 24
    static let MAX_HEIGHT = 24
    
    let filename: String
    let width: Int
    let height: Int
    let rleData: Data
    
    /// Create from raw RGBA pixel data (width * height * 4 bytes)
    init(filename: String, rgba: Data, width: Int, height: Int) {
        self.filename = filename
        self.width = min(width, Self.MAX_WIDTH)
        self.height = min(height, Self.MAX_HEIGHT)
        
        // Convert RGBA to 2-bit grayscale+alpha pixels
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Int(rgba[i])
                let g = Int(rgba[i + 1])
                let b = Int(rgba[i + 2])
                let a = Int(rgba[i + 3])
                
                // Grayscale: average of RGB, take top 2 bits
                let gray = (r + g + b) / 3
                let grayValue = UInt8((gray >> 6) & 0b11)
                
                // Alpha: inverted, shifted
                let alphaValue = UInt8((~a >> 4) & 0b1100)
                
                pixels.append(grayValue | alphaValue)
            }
        }
        
        // RLE encode
        self.rleData = Self.rleEncode(pixels)
    }
    
    static func rleEncode(_ pixels: [UInt8]) -> Data {
        guard !pixels.isEmpty else { return Data() }
        
        var result = Data()
        var lastByte = pixels[0]
        var count: UInt8 = 1
        
        for i in 1..<pixels.count {
            let currentByte = pixels[i]
            if currentByte == lastByte && count < 255 {
                count += 1
            } else {
                result.append(count)
                result.append(lastByte)
                lastByte = currentByte
                count = 1
            }
        }
        result.append(count)
        result.append(lastByte)
        return result
    }
    
    /// Encode for upload to file handle 0x0701
    func encodeForUpload() -> Data {
        let filenameData = filename.data(using: .utf8)! + Data([0x00])
        let entrySize = filenameData.count + 1 + 1 + rleData.count + 2
        
        var data = Data()
        data.append(UInt8(entrySize & 0xFF))
        data.append(UInt8((entrySize >> 8) & 0xFF))
        data.append(filenameData)
        data.append(UInt8(width))
        data.append(UInt8(height))
        data.append(rleData)
        data.append(contentsOf: [0xFF, 0xFF])
        return data
    }
}

extension String {
    var crc32: UInt32 {
        let data = self.data(using: .utf8)!
        return data.withUnsafeBytes { ptr in
            UInt32(bitPattern: Int32(zlib.crc32(0, ptr.baseAddress, UInt32(data.count))))
        }
    }
}
```

---

## References

- `NotificationImagePutRequest.java` - File format for icon uploads
- `NotificationImage.java` - Icon constraints (24x24 max)
- `ImageConverter.java` - Pixel format and encoding
- `RLEEncoder.java` - RLE compression algorithm
- `NotificationFilterPutHRRequest.java` - Filter configuration format
- `PlayNotificationRequest.java` - Notification playback format
- `FossilHRWatchAdapter.java` - Icon/filter initialization
- Fossil HR SDK `DOCUMENTATION.md` - Built-in icons and notification API

## Key Takeaways

1. **Icons are NOT embedded in notifications** - they're uploaded separately and referenced by CRC
2. **Built-in icons exist** (`icTimer`, `icStopwatch`, etc.) - no upload needed for these
3. **The `general_white.bin` fallback** - generic icon for unknown apps
4. **24x24 max size** - icons are small for the e-ink display
5. **2-bit grayscale** - only 4 shades of gray, matching the e-ink display capability
