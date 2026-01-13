# Gadgetbridge Git Submodule

This repository includes the [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) project as a Git submodule for reliable reference to the primary source of the Fossil Hybrid HR protocol implementation.

## Location

The Gadgetbridge repository is located at:
```
external/Gadgetbridge/
```

## Initial Setup

When cloning this repository for the first time, initialize the submodule:

```bash
# Clone the main repository
git clone https://github.com/joshspicer/hybrid-hr-bridge.git
cd hybrid-hr-bridge

# Initialize and update the submodule
git submodule update --init --recursive
```

Alternatively, clone with submodules in one command:
```bash
git clone --recurse-submodules https://github.com/joshspicer/hybrid-hr-bridge.git
```

## Keeping Gadgetbridge Updated

The submodule tracks a specific commit of Gadgetbridge. To update to the latest version:

```bash
# Navigate to the submodule directory
cd external/Gadgetbridge

# Fetch the latest changes
git fetch origin

# Checkout the latest master branch
git checkout master
git pull origin master

# Return to the main repository root
cd ../..

# Stage the submodule update
git add external/Gadgetbridge

# Commit the update
git commit -m "Update Gadgetbridge submodule to latest"
```

### One-Line Update Command

For convenience, update the submodule from the repository root:

```bash
git submodule update --remote --merge external/Gadgetbridge
```

This command:
- Fetches the latest changes from the remote repository
- Merges them into the local submodule
- Updates the submodule to track the latest commit

After running this, commit the change:
```bash
git add external/Gadgetbridge
git commit -m "Update Gadgetbridge submodule to latest"
```

## Key Protocol Implementation Files

The Fossil Hybrid HR protocol implementation in Gadgetbridge is primarily located at:
```
external/Gadgetbridge/app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/qhybrid/
```

Key directories:
- `requests/fossil_hr/` - Hybrid HR specific protocol requests
- `requests/fossil/` - General Fossil protocol requests
- `file/` - File handle and file transfer implementations
- `adapter/` - Device adapters and coordinators

## Cross-Referencing Protocol Documentation

When implementing features from `docs/PROTOCOL_SPECIFICATION.md`, always cross-reference with the actual Gadgetbridge source code in the submodule. The documentation includes links to specific files and line numbers for easy reference.

Example workflow:
1. Read protocol specification in `docs/PROTOCOL_SPECIFICATION.md`
2. Navigate to the referenced file in `external/Gadgetbridge/`
3. Review the actual Java implementation
4. Implement the equivalent Swift code in this project
5. Add source comments referencing the Gadgetbridge file

## Checking Current Version

To see which commit the submodule is currently tracking:

```bash
git submodule status
```

Or from within the submodule directory:
```bash
cd external/Gadgetbridge
git log -1
```

## Why Use a Submodule?

Including Gadgetbridge as a submodule provides:
- **Reliable Primary Source**: Always have the exact source code that protocol implementations reference
- **Version Tracking**: Know which version of Gadgetbridge was used for each implementation
- **Offline Access**: Work on protocol implementations without internet connectivity
- **Accuracy**: Eliminate discrepancies between documentation and actual implementation

## Submodule Best Practices

1. **Keep Updated**: Periodically update the submodule to catch protocol improvements
2. **Reference Commits**: When documenting protocol features, include both the file path and commit hash
3. **Don't Modify**: The submodule is read-only for reference - don't make changes in `external/Gadgetbridge/`
4. **Commit Updates**: When updating the submodule, commit the change to track which version is being referenced

## Additional Resources

- [Gadgetbridge Repository](https://codeberg.org/Freeyourgadget/Gadgetbridge)
- [Git Submodules Documentation](https://git-scm.com/book/en/v2/Git-Tools-Submodules)
- [Gadgetbridge Fossil Protocol Discussion](https://codeberg.org/Freeyourgadget/Gadgetbridge/wiki)
