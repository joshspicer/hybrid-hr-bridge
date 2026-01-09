# Testing Notes for Verbose Logging and Background Support

## Changes Made

### 1. LogManager Utility
- **File**: `hybridHRBridge/hybridHRBridge/Utilities/LogManager.swift`
- **Purpose**: Centralized logging system with file export capability
- **Features**:
  - Captures all logs with timestamps, levels (DEBUG, INFO, WARNING, ERROR), and categories
  - Stores up to 5000 entries in memory
  - Logs to both console and OS logger (for crash reports)
  - Export basic logs or detailed logs with statistics
  - Share functionality via iOS share sheet

### 2. Enhanced Authentication Logging
- **File**: `hybridHRBridge/hybridHRBridge/Protocol/AuthenticationManager.swift`
- **Changes**:
  - Added detailed logging at every step of authentication flow
  - Logs phone random number generation
  - Logs challenge/response data (in hex format for debugging)
  - Logs decryption success/failure
  - Logs verification steps
  - Enhanced timeout error with current state information
  - All data includes hex representations for protocol debugging

### 3. Enhanced Bluetooth Logging
- **File**: `hybridHRBridge/hybridHRBridge/Bluetooth/BluetoothManager.swift`
- **Changes**:
  - Logs Bluetooth state changes with emoji indicators
  - Logs device discovery with RSSI and UUIDs
  - Logs connection attempts and results
  - Logs service and characteristic discovery
  - Logs all read/write operations with data payloads
  - Logs notification enable/disable events
  - **State Restoration**: Enabled CoreBluetooth state restoration with identifier "com.hybridhrbridge.central"

### 4. Settings Persistence Fix
- **File**: `hybridHRBridge/hybridHRBridge/Services/WatchManager.swift`
- **Changes**:
  - Added explicit `userDefaults.synchronize()` call to force immediate save
  - Added logging when saving devices

### 5. Log Export UI
- **File**: `hybridHRBridge/hybridHRBridge/Views/DeviceDetailView.swift`
- **New Features**:
  - "Export Debug Logs" button in Actions section
  - Shows log summary (total entries, errors, warnings)
  - Two export options:
    - **Basic Logs**: Plain chronological log entries
    - **Detailed Logs**: Includes statistics, error summary, and full logs
  - Share sheet integration for easy export to email, files, etc.
  - Clear logs button to free memory

### 6. Background Bluetooth Support
- **File**: `hybridHRBridge/hybridHRBridge.xcodeproj/project.pbxproj`
- **Status**: Already configured!
- The project already has `bluetooth-central` background mode enabled
- CoreBluetooth state restoration has been enabled in code

## Testing Instructions

### Test 1: Connection and Authentication with Logging
1. Open the app
2. Scan for your watch
3. Connect to the watch
4. Wait for authentication to complete (or timeout)
5. Navigate to Watch detail view
6. Tap "Export Debug Logs"
7. Choose "Export Detailed Logs"
8. Share the log file to yourself via email/files
9. **Verify**: The log file contains:
   - Bluetooth connection steps
   - Service/characteristic discovery
   - Authentication challenge/response flow
   - Hex data for all protocol messages

### Test 2: Authentication Timeout Debugging
If authentication times out:
1. Export detailed logs immediately after timeout
2. Check the log file for:
   - "Authentication timed out after 10 seconds"
   - Phone random number
   - Watch random number (if received)
   - Any error messages about characteristic discovery
   - BLE connection state

### Test 3: Settings Persistence
1. Connect to a watch and save it
2. Set a secret key for the watch
3. Force close the app (swipe up in app switcher)
4. Reopen the app
5. **Verify**: Your saved watch and secret key are still there

### Test 4: Background Connection (iOS Device Only)
**Note**: This cannot be tested in simulator
1. Connect to watch on physical iPhone
2. Go to Home screen (don't force close)
3. Lock the iPhone
4. Wait a few minutes
5. Unlock and return to app
6. **Verify**: Connection is still active

## Common Issues to Watch For

### Authentication Timeout
If you see "authentication timed out":
- Check logs for "Received response from watch" - did the watch respond at all?
- Check for "Characteristic discovery failed" - are all characteristics available?
- Check for "No handler registered" - is the notification handler properly set up?

### Connection Drops
If connection drops frequently:
- Check logs for "Disconnection was unexpected" vs "Clean disconnection"
- Look for error details in disconnect logs
- Check for "Bluetooth is resetting" messages

### Settings Not Saving
If secret keys aren't persisting:
- Check logs for "Saved X devices to UserDefaults"
- Verify the app isn't being deleted/reinstalled between tests

## Log Categories to Look For

- **BLE**: All Bluetooth operations (scanning, connecting, discovering, reading, writing)
- **Auth**: Authentication flow and AES encryption/decryption
- **LogManager**: Logging system operations

## Sending Logs to Developer/LLM

When exporting logs for debugging:
1. Use "Export Detailed Logs" option
2. Reproduce the issue first, then export immediately
3. The detailed export includes:
   - System information (iOS version, device model)
   - Log statistics
   - Recent errors summary
   - Full chronological log

This gives developers/LLMs all the information needed to diagnose connection and authentication issues!
