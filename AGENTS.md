# AGENTS.md

Rules and guidelines for AI agents working on this repository.

## Project Overview

This is an iOS app (SwiftUI) that communicates with Fossil/Skagen Hybrid HR watches over Bluetooth Low Energy. It replicates functionality from the discontinued official Fossil app using the reverse-engineered protocol from [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) and other sources.

## Architecture

```
hybridHRBridge/
├── Bluetooth/           # CoreBluetooth device discovery & connection
├── Protocol/            # BLE protocol implementation (auth, file transfer)
├── Services/            # High-level watch functionality coordination
├── Models/              # Data models
├── Views/               # SwiftUI views
└── Utilities/           # Helpers (CRC32, AES, ByteBuffer)
```

## Key Technical Details

### Bluetooth Protocol
- **Service UUID**: `3dda0001-957f-7d4a-34a6-74696673696d`
- All multi-byte values use **little-endian** byte order
- Authentication uses **AES-128 CBC** with zero IV
- File transfers use characteristics `3dda0003` (operations) and `3dda0004` (data)

### Important Files
- `docs/PROTOCOL_SPECIFICATION.md` - Complete BLE protocol spec with Gadgetbridge source links
- `docs/IMPLEMENTATION_GUIDE.md` - Architecture overview and implementation phases
- `FossilConstants.swift` - All UUIDs, commands, and protocol constants
- `FileHandle.swift` - File handle definitions for different data types

## Coding Guidelines

### Swift Style
- Use `@MainActor` for UI-related classes
- Use `async/await` for asynchronous operations
- Prefer `@Published` properties in `ObservableObject` classes for reactive UI
- Keep protocol implementations close to Gadgetbridge Java source for reference

### Documentation
- Reference Gadgetbridge source files when implementing protocol features
- Include source links in comments (e.g., `// Source: VerifyPrivateKeyRequest.java#L40-L134`)
- Update `docs/PROTOCOL_SPECIFICATION.md` when discovering new protocol details

### Debug Logging
- **ALWAYS** add entries to the in-app debug log for any important changes, operations, or state transitions
- Use `LogManager.shared` singleton for centralized logging that persists in-app and can be exported
- Initialize a logger instance in your class: `private let logger = LogManager.shared`
- Log categories for consistent organization:
  - `"BLE"` - Bluetooth operations (discovery, connection, data transfer)
  - `"Auth"` - Authentication steps and key management
  - `"Protocol"` - BLE protocol messages and file transfers
  - `"UI"` - User-initiated actions and view transitions
  - `"FileTransfer"` - File upload/download operations
  - Use component/class name for other operations (e.g., `"WatchManager"`, `"RequestBuilder"`)
- Log levels:
  - `.debug()` - Detailed technical data (hex dumps, state details, verbose operation info)
  - `.info()` - Normal operations (connection established, command sent, operation completed)
  - `.warning()` - Recoverable issues (retries, fallbacks, unexpected but handled states)
  - `.error()` - Failures that prevent operation (connection failures, authentication errors, invalid data)
- Log at key points:
  - Start of async operations: `logger.info("BLE", "Starting scan for devices")`
  - Completion: `logger.info("BLE", "Connected to \(device.name)")`
  - State changes: `logger.debug("Auth", "Auth state changed to: \(newState)")`
  - Data transfers: `logger.debug("Protocol", "Sending \(data.count) bytes: \(data.hexString)")`
  - Errors: `logger.error("BLE", "Connection failed: \(error.localizedDescription)")`
- Users can export logs via the Debug Logs screen for troubleshooting
- Example usage:
```swift
final class MyManager {
    private let logger = LogManager.shared

    func performOperation() async throws {
        logger.info("MyManager", "Starting operation")

        do {
            let result = try await someAsyncCall()
            logger.debug("MyManager", "Operation result: \(result)")
            logger.info("MyManager", "Operation completed successfully")
        } catch {
            logger.error("MyManager", "Operation failed: \(error.localizedDescription)")
            throw error
        }
    }
}
```

### Testing
- Bluetooth cannot be tested in the simulator - requires physical device
- Console `print()` statements are acceptable for temporary debugging but should not replace LogManager for persistent logs

## External References

ALWAYS CROSS REFERENCE WITH A RELIABLE PRIMARY SOURCE BEFORE ANY CHANGE!

- **Gadgetbridge Source**: https://codeberg.org/Freeyourgadget/Gadgetbridge
  - Local clone at `/Users/josh/git/Gadgetbridge`
  - One Key path: `app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/`
- **Fossil HR SDK**: https://github.com/dakhnod/Fossil-HR-SDK (for building custom watch apps)
- **Apple Docs**: Use the `apple-developer-docs-mcp` to fetch iOS specific information (eg: bluetooth classes, etc.)

Search on the internet for a reliable source whenever unsure.  This is NOT the kind of project to guess or make up values! The data (eg: bluetooth characteristics) MUST be precise and grounded in a primary source. Add comments referring to this sources whenever used to help later.

## Build & Run

```bash
# Build for simulator (UI testing only - BLE won't work)
xcodebuild -project hybridHRBridge/hybridHRBridge.xcodeproj -scheme hybridHRBridge -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# For actual BLE testing, deploy to physical iPhone
```

Use the XcodeMCP Server to check if a physical iPhone is connected. If it is, deploy to the iPhone and test live by connecting to the watch, taking screenshots, inspecting logs, etc...

## Common Tasks

### Adding a new file handle
1. Add case to `FileHandle.swift` enum
2. Reference `FileHandle.java` in Gadgetbridge for correct major/minor values
3. Add debug logging for file handle operations

### Implementing new protocol feature
1. Find corresponding Java class in Gadgetbridge (`requests/fossil_hr/` or `requests/fossil/`)
2. Document the source file and line numbers
3. Implement in Swift following existing patterns in `Protocol/` directory
4. **Add debug logging** for the new protocol operations (start, completion, errors)
5. Add high-level API in `WatchManager.swift`

### Adding UI for new feature
1. Create view in `Views/` directory
2. Wire to `WatchManager` via `@EnvironmentObject`
3. Handle async operations with proper loading/error states
4. **Add info-level logging** for user-initiated actions to help with troubleshooting

### General Rule: Always Add Logging
For **any** implementation work:
- Add logging at the start of operations
- Add logging for state changes
- Add logging for completion (success or failure)
- This helps with debugging BLE issues and user support
