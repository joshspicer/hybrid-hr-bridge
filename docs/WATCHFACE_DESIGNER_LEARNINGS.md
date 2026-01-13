# Watchface Designer Implementation Learnings

This document captures all learnings from the attempted implementation of a custom watchface designer for Fossil Hybrid HR watches. The implementation ultimately failed due to CRC validation issues, but significant protocol knowledge was gained.

## Summary

**Goal**: Build and upload custom watchfaces with configurable widgets and background images.

**Outcome**: File transfer protocol works correctly, but the watch rejects the uploaded `.wapp` file during the "close" operation with `VERIFICATION_FAIL (0x05)` indicating a CRC mismatch in the embedded CRC32C checksum.

---

## What Works ✅

### 1. File Transfer Protocol
The BLE file transfer protocol is working correctly:
- **Command Sequence**: PUT header → ACK → Data chunks → Close → Verify
- **Header Format**: `[0x03][handle:2][offset:4][size:4][size:4]` (15 bytes)
- **Data Chunking**: 244-byte packets with flow control
- **Transfer CRC**: Standard CRC32 (zlib) is correctly calculated and verified
- **Flow Control**: Must respect `canSendWriteWithoutResponse` for BLE throughput

```
[FileTransfer] Calculated CRC32: 0x5E2B7731 over 26507 bytes
[FileTransfer] ✅ CRC verified, sending close command
```

### 2. JSON Configuration Protocol
Sending JSON to configure watch settings works:
- Handle format: `0x0500 | jsonIndex` where jsonIndex increments per request
- Used for watchface activation via `themeApp._.config.selected_theme`

### 3. Widget Binary Format
Widget binaries from Gadgetbridge work and can be embedded:
- Files like `widgetDate.bin`, `widgetHR.bin`, etc.
- JRRY format (JavaScript Runtime?)
- ~134KB total for all widgets embedded via `WidgetBinaries.swift`

### 4. Image Conversion
2-bit grayscale image encoding works:
- 240x240 RAW format for backgrounds
- 4 pixels per byte, bottom-up storage
- Grayscale quantization: gray value >> 6 to get 2-bit (0-3)

---

## What Doesn't Work ❌

### 1. Embedded CRC32C Validation
The watch validates an embedded CRC32C checksum inside the `.wapp` file and rejects our files:

```
[FileTransfer] ❌ File close failed: VERIFICATION_FAIL (CRC mismatch) (status: 0x05)
```

The `.wapp` file format requires a trailing CRC32C (Castagnoli polynomial) that the watch verifies against the file content.

**Attempted CRC32C Implementation**:
```swift
// Castagnoli polynomial (reflected): 0x82F63B78
// Init: 0xFFFFFFFF, Final XOR: 0xFFFFFFFF
// Test vector: "123456789" should produce 0xE3069283
```

**Suspected Issues**:
1. Wrong data range being CRC'd (content only vs. full file?)
2. Byte order issues
3. Implementation might not match Gadgetbridge's 8-way unrolled table

### 2. JSON Widget Configuration (Firmware >= 2.20)
The original approach of sending widget configuration via JSON **does not work** on newer firmware:

```swift
// This works on firmware < 2.20 but is IGNORED on >= 2.20
{
  "push": {
    "set": {
      "complication.0.pos": {"x": 120, "y": 58},
      "complication.0.type": "widgetDate"
    }
  }
}
```

**Discovery**: Firmware 2.20+ bakes widgets into the watchface `.wapp` file. They cannot be changed separately.

---

## Protocol Details

### .wapp File Format

```
Structure:
┌─────────────────┬───────────────────────────────────┐
│ Handle          │ 2 bytes (0xFE15 for APP_CODE)     │
│ Version         │ 2 bytes (0x0003)                  │
│ Offset          │ 4 bytes (0x00000000)              │
│ Size            │ 4 bytes (content length)          │
│ Content         │ Variable                          │
│ CRC32C          │ 4 bytes (over content only!)      │
└─────────────────┴───────────────────────────────────┘
```

### Content Structure (from FossilAppWriter.java)

```
Content:
┌─────────────────┬────────────────────────────────────┐
│ Type            │ 1 byte (1=watchface, 2=app)        │
│ Version         │ 3 bytes (e.g., 1.0.0)              │
│ Offset Table    │ 9x UInt32 (section offsets)        │
│ Padding         │ To 88 bytes total header           │
├─────────────────┼────────────────────────────────────┤
│ Code Section    │ [nameLen][name\0][dataLen][data]   │
│ Icons Section   │ Same format (empty for basic)      │
│ Layout Section  │ Same format (background.raw)       │
│ DisplayName     │ [nameLen][name\0][valueLen][val\0] │
│ Config Section  │ [nameLen][name\0][valueLen][val\0] │
└─────────────────┴────────────────────────────────────┘
```

### CRC Types Used

| Context | CRC Type | Notes |
|---------|----------|-------|
| File Transfer Protocol | CRC32 (zlib) | `java.util.zip.CRC32` |
| Embedded in .wapp | CRC32C (Castagnoli) | `nodomain.freeyourgadget.gadgetbridge.util.CRC32C` |

**This distinction is critical and was a major source of bugs.**

### BLE Flow Control

Must check `CBPeripheralDelegate.peripheralIsReady(toSendWriteWithoutResponse:)` before each packet when using `.writeWithoutResponse`. Without this, packets are dropped silently.

---

## Key Gadgetbridge References

### Files to Study

| File | Purpose |
|------|---------|
| `FossilAppWriter.java` | .wapp file construction |
| `FilePutRawRequest.java` | File transfer protocol |
| `HybridHRWatchfaceFactory.java` | Widget layout and offset calculations |
| `ImageConverter.java` | 2-bit image encoding |
| `CRC32C.java` | CRC32C checksum implementation |
| `FossilHRWatchAdapter.java` | High-level coordination |

### Gadgetbridge CRC32C Implementation

```java
// From: app/src/main/java/nodomain/freeyourgadget/gadgetbridge/util/CRC32C.java
// Uses 8-way unrolled lookup tables (T8_0 through T8_7)
// Init: ~0 (0xFFFFFFFF)
// Final: ~ret & 0xffffffffL
```

---

## Implementation Artifacts

### Files Created

| File | Purpose | Status |
|------|---------|--------|
| `WatchfaceBuilder.swift` | Constructs .wapp files | CRC issue |
| `WatchImageConverter.swift` | 2-bit RAW/RLE encoding | Works |
| `WidgetBinaries.swift` | Embedded widget .bin files | Works |
| `WatchfaceDesignerView.swift` | UI for watchface design | Works |
| `WidgetEditorView.swift` | JSON widget config UI | Firmware limitation |
| `CRC32.swift` (modified) | Added CRC32C implementation | Possibly buggy |

### Widget Binaries (~134KB total)

Extracted from Gadgetbridge and embedded:
- `openSourceWatchface.bin` - Main watchface code
- `widgetDate.bin` - Date widget
- `widgetHR.bin` - Heart rate widget
- `widgetSteps.bin` - Steps widget
- `widgetBattery.bin` - Battery widget
- `widgetCalories.bin` - Calories widget
- `widgetActiveMins.bin` - Active minutes widget
- `widgetWeather.bin` - Weather widget
- `widget2ndTZ.bin` - Second timezone widget
- `widgetChanceOfRain.bin` - Rain chance widget
- `widgetUV.bin` - UV index widget
- `widgetSpO2.bin` - SpO2 widget
- `widgetCustom.bin` - Custom text widget

---

## Next Steps to Fix

### Option 1: Debug CRC32C Implementation

1. Verify test vector: `CRC32C("123456789")` should equal `0xE3069283`
2. Compare byte-by-byte with Gadgetbridge's lookup tables
3. Check if CRC is computed over content only vs entire file
4. Verify endianness of CRC in file

### Option 2: Extract from Gadgetbridge

Instead of implementing CRC32C from scratch:
1. Use Gadgetbridge app to upload watchface
2. Capture the BLE traffic (nRF Connect or similar)
3. Compare byte-for-byte with our generated file
4. Identify exactly where the mismatch occurs

### Option 3: Use Gadgetbridge Directly

The most reliable path:
1. Build watchface using Gadgetbridge codebase
2. Port the exact Java CRC32C implementation with lookup tables
3. Match the exact byte sequence they produce

---

## Test Log Output (Final Attempt)

```
[WatchfaceBuilder] Building watchface 'MyWatchface' with 4 widgets
[WatchfaceBuilder] CRC32C test: '123456789' = 0x________ (expected: 0xE3069283)
[WatchfaceBuilder] Section sizes: code=25814, icons=0, layout=14415, display=37, config=517
[WatchfaceBuilder] Content size: 26491 bytes
[WatchfaceBuilder] Built watchface: 26507 bytes (CRC: 0xB98AF9EC)
[FileTransfer] Calculated CRC32: 0x5E2B7731 over 26507 bytes
[FileTransfer] ✅ CRC verified, sending close command
[FileTransfer] ❌ File close failed: VERIFICATION_FAIL (CRC mismatch) (status: 0x05)
```

**Key Observation**: Transfer CRC32 succeeds, but embedded CRC32C fails.

---

## Lessons Learned

1. **Read Gadgetbridge source carefully** - The protocol uses TWO different CRC algorithms in different contexts
2. **Firmware versions matter** - Widget configuration only works on older firmware; newer firmware requires .wapp files
3. **BLE flow control is critical** - Use `canSendWriteWithoutResponse` to avoid dropped packets
4. **Test with known vectors** - Always verify CRC implementations with standard test vectors before integration
5. **Keep Gadgetbridge clone handy** - The Java source is the definitive reference for this protocol
6. **Log everything** - Detailed hex dumps are essential for debugging binary protocols

---

## Appendix: Protocol Commands

| Command | Code | Description |
|---------|------|-------------|
| File Put | 0x03 | Start file upload |
| File Close | 0x04 | Complete upload |
| File Get | 0x01 | Request file download |
| File Delete | 0x05 | Delete file |

| Status Code | Value | Meaning |
|-------------|-------|---------|
| SUCCESS | 0x01 | Operation succeeded |
| ERROR | 0x02 | General error |
| REQUEST_DATA | 0x0A | Ready for more data |
| VERIFICATION_FAIL | 0x05 | CRC mismatch |

---

*Document created: January 2026*
*Status: Implementation paused pending CRC32C fix*
