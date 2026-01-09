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

### Testing
- Bluetooth cannot be tested in the simulator - requires physical device
- Use `print("[Component] message")` logging pattern for debugging BLE communication

## External References

ALWAYS CROSS  REFERENCES WITH A RELIABLE PRIMARY SOURCE BEFORE ANY CHANGE!

- **Gadgetbridge Source**: https://codeberg.org/Freeyourgadget/Gadgetbridge
  - Local clone at `/Users/jospicer/dev/Gadgetbridge` or `/Users/josh/git/Gadgetbridge`
  - Key path: `app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/`
- **Fossil HR SDK**: https://github.com/dakhnod/Fossil-HR-SDK (for building custom watch apps)
- **Apple Docs**: Use the `apple-developer-docs-mcp` to fetch iOS specific information (eg: bluetooth classes, etc.)

Search on the internet for a reliable source whenever unsure.  This is NOT the kind of project to guess or make up values! The data (eg: bluetooth characteristics) MUST be precise and grounded in a primary source. Add comments referring to this sources whenever used to help later.

## Build & Run

```bash
# Build for simulator (UI testing only - BLE won't work)
xcodebuild -project hybridHRBridge/hybridHRBridge.xcodeproj -scheme hybridHRBridge -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# For actual BLE testing, deploy to physical iPhone
```

## Common Tasks

### Adding a new file handle
1. Add case to `FileHandle.swift` enum
2. Reference `FileHandle.java` in Gadgetbridge for correct major/minor values

### Implementing new protocol feature
1. Find corresponding Java class in Gadgetbridge (`requests/fossil_hr/` or `requests/fossil/`)
2. Document the source file and line numbers
3. Implement in Swift following existing patterns in `Protocol/` directory
4. Add high-level API in `WatchManager.swift`

### Adding UI for new feature
1. Create view in `Views/` directory
2. Wire to `WatchManager` via `@EnvironmentObject`
3. Handle async operations with proper loading/error states
