# Hybrid HR Bridge

iOS companion app for Fossil/Skagen Hybrid HR smartwatches, with the goal of replicating functionality from the discontinued official Fossil app.

## Features

- Bluetooth Low Energy communication with Hybrid HR watches
- AES-128 authentication using keys from Gadgetbridge
- Device discovery and connection management
- Protocol implementation based on [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge)

## Documentation

- [Protocol Specification](docs/PROTOCOL_SPECIFICATION.md) - BLE protocol details as discovered so far by reverse engineering (may contain inaccuracies or omissions)
## Getting Started

### Prerequisites

1. A Fossil or Skagen Hybrid HR smartwatch
2. The secret key extracted by MITM'ing skagen app when on first pair of the watch (see [GadgetBridge's docs on this](https://gadgetbridge.org/basics/pairing/fossil-server/))
3. Git with submodule support for accessing the Gadgetbridge reference implementation

### Cloning the Repository

This repository includes Gadgetbridge as a Git submodule for protocol reference. Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/joshspicer/hybrid-hr-bridge.git
```

Or if you've already cloned without submodules:

```bash
git submodule update --init --recursive
```

For more details on managing the Gadgetbridge submodule, see [docs/GADGETBRIDGE_SUBMODULE.md](docs/GADGETBRIDGE_SUBMODULE.md).

### Extracting Your Device Key

The app requires a device-specific secret key from Gadgetbridge. See the [Troubleshooting Guide](docs/TROUBLESHOOTING.md#how-to-extract-the-correct-key-from-gadgetbridge) for detailed instructions.

**Quick method using ADB:**
```bash
adb shell "run-as nodomain.freeyourgadget.gadgetbridge cat /data/data/nodomain.freeyourgadget.gadgetbridge/shared_prefs/DEVICE_[MAC_ADDRESS].xml" | grep authkey
```

### Building & Running

```bash
cd hybridHRBridge
xcodebuild -project hybridHRBridge.xcodeproj -scheme hybridHRBridge
```

**Note:** Bluetooth functionality requires a physical iOS device - it won't work in the simulator.

## Troubleshooting

If you see "Authentication rejected by watch" errors, see the [Troubleshooting Guide](docs/TROUBLESHOOTING.md) for help extracting the correct key from Gadgetbridge.

## References

- [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) - Open source Android app (protocol source)
- [Fossil HR SDK](https://github.com/dakhnod/Fossil-HR-SDK) - For building custom watch apps

## License

This project is for educational and interoperability purposes. The Fossil Hybrid HR protocol implementation is based on reverse-engineering work by the Gadgetbridge project.
