# Custom Watch Apps

This document describes the custom watch app feature in Hybrid HR Bridge.

## Overview

The Fossil/Skagen Hybrid HR watches support custom applications written in JerryScript (JavaScript for embedded systems). This app provides infrastructure for:

1. **Building .wapp files** - The native watch app format
2. **Installing apps** - Upload apps to your watch via Bluetooth
3. **Managing apps** - Configure and update watch applications

## App Tab

The new "Apps" tab provides:

- **Custom Text Display** - Demonstration of building custom apps
- **Install from File** - Install pre-built .wapp files
- **Resources** - Links to Fossil HR SDK and development tools

## Custom Text Display App

This feature demonstrates the complete .wapp file creation infrastructure:

### What It Does

- Shows UI for configuring custom text
- Builds a .wapp file with proper structure
- Demonstrates all components: header, code section, layout, icons
- Can attempt installation to the watch

### Limitations

The demo app creates a structurally valid .wapp file but has a stub JerryScript code section. For fully functional apps, you need:

1. **JerryScript 2.1.0 compiler** (jerry-snapshot tool)
2. **Proper app code** that responds to watch events
3. **Layout files** that define the UI
4. **Icon files** for the app launcher

### Why This Limitation?

Compiling JerryScript code requires:
- The jerry-snapshot command-line tool
- Proper build environment (Linux/macOS with build tools)
- The Fossil HR SDK

These aren't available in an iOS app runtime environment. Instead:

- Build apps externally using the SDK
- Install them using the "Install from File" feature
- The demo shows how the infrastructure works

## Installing Working Apps

### Option 1: Pre-Built Apps

Download pre-built .wapp files from:
- [Fossil HR Gadgetbridge Apps](https://codeberg.org/Freeyourgadget/fossil-hr-gbapps)
- [Fossil HR SDK Examples](https://github.com/dakhnod/Fossil-HR-SDK/tree/main/examples)

Then use "Install from File" in the Apps tab.

### Option 2: Build Your Own

1. **Set up the Fossil HR SDK:**
   ```bash
   git clone https://github.com/dakhnod/Fossil-HR-SDK.git
   cd Fossil-HR-SDK
   ```

2. **Install prerequisites:**
   - JerryScript 2.1.0 with snapshot support
   - Python 3 with crc32c: `pip3 install crc32c`
   - make, adb (for testing)

3. **Create or modify an example:**
   ```bash
   cd examples/simple-menu
   # Edit app.js
   make compile  # Compile JavaScript to snapshot
   make pack     # Create .wapp file
   ```

4. **Install via Hybrid HR Bridge:**
   - Transfer the .wapp to your iPhone
   - Use "Install from File" in the Apps tab

## .wapp File Structure

Our WatchAppBuilder utility creates files with this structure:

```
File Header (14 bytes):
- File Handle: 0xFE15 (APP_CODE)
- Version: 0x0003
- Offset: 0x00000000
- File Size: 4 bytes (little-endian)

Content Block:
├── Header (88 bytes)
│   ├── Version (4 bytes): X.Y.Z.W
│   ├── Reserved (8 bytes)
│   └── Section Offsets (76 bytes)
├── Code Section
│   └── Compiled JerryScript snapshot
├── Icons Section
│   └── Compressed icon images
├── Layout Section
│   └── JSON layout files (null-terminated)
├── Display Name Section
│   └── App name shown on watch
└── Config Section
    └── App configuration data

CRC32C Checksum (4 bytes):
- Castagnoli CRC32 of content block
```

### Section Details

Each section contains files in this format:
```
- Filename length (1 byte, including null terminator)
- Filename (UTF-8 string)
- Null terminator (1 byte)
- File size (2 bytes, little-endian)
- File contents
```

## App Development Resources

### Essential Links

- **Fossil HR SDK**: https://github.com/dakhnod/Fossil-HR-SDK
  - Complete SDK with examples
  - Documentation on API and events
  - Build tools and scripts

- **Gadgetbridge Apps**: https://codeberg.org/Freeyourgadget/fossil-hr-gbapps
  - Open source watchfaces and apps
  - Working examples you can study
  - Pre-built .wapp files

- **Community Forum**: https://github.com/Freeyourgadget/Gadgetbridge/discussions
  - Ask questions about app development
  - Share your creations
  - Get help with issues

### Documentation

- [SDK Documentation](https://github.com/dakhnod/Fossil-HR-SDK/blob/main/DOCUMENTATION.md)
- [Gadgetbridge Fossil Hybrid HR Guide](https://gadgetbridge.org/internals/specifics/fossil-hybrid/)
- [JerryScript Documentation](https://jerryscript.net/)

## App Structure Example

A minimal working app in JerryScript:

```javascript
return {
    node_name: '',
    manifest: {
        timers: []
    },
    
    handler: function (event, response) {
        // Handle system events
        if (event.type === 'system_state_update' && 
            event.de === true && 
            event.le === 'visible') {
            
            // Move watch hands out of the way
            response.move = {
                h: 270,
                m: 90,
                is_relative: false
            };
            
            // Draw the UI
            response.draw = {
                update_type: 'du4'
            };
            response.draw[this.node_name] = {
                layout_function: 'layout_parser_json',
                layout_info: {
                    json_file: 'my_layout'
                }
            };
        }
    },
    
    init: function () {
        // Initialize the app
    }
}
```

## Troubleshooting

### App Won't Install

- Ensure watch is authenticated
- Check file is a valid .wapp
- Verify Bluetooth connection is stable
- Check debug logs for details

### App Installed But Won't Run

- The demo app has a stub code section
- Use pre-built .wapp files for working apps
- Build apps with the Fossil HR SDK

### Watch Shows Error

- App may be incompatible with firmware version
- JerryScript version must be 2.1.0
- Check app code for errors

## Future Enhancements

Possible improvements:

1. **Server-Side Compilation**
   - Host a compilation service
   - Upload JavaScript, get back .wapp
   - No local SDK needed

2. **Pre-Built App Library**
   - Bundle common apps as resources
   - Easy one-tap installation
   - Curated app collection

3. **App Templates**
   - Visual app builder
   - Pre-made templates
   - Drag-and-drop interface

4. **Configuration Protocol**
   - Send config to installed apps
   - Update app data without reinstalling
   - Dynamic content updates

## Contributing

Want to improve the custom apps feature? Check out:

- The WatchAppBuilder utility in `Utilities/WatchAppBuilder.swift`
- App views in `Views/AppsView.swift` and `Views/CustomTextAppView.swift`
- File transfer logic in `Protocol/FileTransferManager.swift`

Pull requests welcome!
