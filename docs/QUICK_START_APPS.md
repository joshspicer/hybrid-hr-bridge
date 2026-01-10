# Quick Start: Custom Watch Apps

## Installing Pre-Built Apps (Recommended)

The easiest way to get working watch apps:

### Step 1: Download a .wapp File

Get apps from these sources:

**Gadgetbridge Community Apps:**
```bash
# Clone the repository
git clone https://codeberg.org/Freeyourgadget/fossil-hr-gbapps.git

# Find .wapp files
cd fossil-hr-gbapps/watchface
# Look for: reversed_watchface.wapp
```

**Fossil HR SDK Examples:**
```bash
# Clone the SDK
git clone https://github.com/dakhnod/Fossil-HR-SDK.git

# Browse examples
cd Fossil-HR-SDK/examples
# timer/, snake/, simple-menu/
```

### Step 2: Install via Hybrid HR Bridge

1. Transfer the .wapp file to your iPhone
2. Open Hybrid HR Bridge
3. Connect to your watch
4. Authenticate
5. Go to **Apps** tab
6. Tap **"Install from File"**
7. Select your .wapp file
8. Wait for upload to complete

### Step 3: Use on Watch

1. On your watch, open the app menu
2. Find your newly installed app
3. Launch it!

## Building Your Own Apps

Want to create custom watch apps? Follow these steps:

### Prerequisites

You'll need:
- macOS or Linux computer
- JerryScript 2.1.0 with snapshot support
- Python 3 with crc32c
- make and basic build tools

### Setup

```bash
# 1. Clone the Fossil HR SDK
git clone https://github.com/dakhnod/Fossil-HR-SDK.git
cd Fossil-HR-SDK

# 2. Install dependencies
# On macOS:
brew install python3 make

# On Linux:
sudo apt install python3 make

# Install Python dependencies
pip3 install crc32c

# 3. Build and install JerryScript 2.1.0
# See: https://jerryscript.net/getting-started/
```

### Create Your First App

1. **Start from an example:**

```bash
cd Fossil-HR-SDK/examples/simple-menu
cp -r . ~/my-first-app
cd ~/my-first-app
```

2. **Edit app.js:**

```javascript
return {
    node_name: '',
    manifest: {
        timers: []
    },
    
    handler: function (event, response) {
        if (event.type === 'system_state_update' && 
            event.de === true && 
            event.le === 'visible') {
            
            // Your app logic here
            response.move = {
                h: 270,  // Move hour hand
                m: 90,   // Move minute hand
                is_relative: false
            };
            
            // Draw something
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
        // Initialize
    }
}
```

3. **Build the app:**

```bash
# Update build/app.json with your app identifier
# Then:
make compile  # Compile JS to JerryScript snapshot
make pack     # Create .wapp file
```

4. **Install to watch:**

Transfer the .wapp to your iPhone and use Hybrid HR Bridge's "Install from File" feature.

## Demo: Custom Text Display

The app includes a demonstration feature:

1. Open Hybrid HR Bridge
2. Go to **Apps** tab
3. Tap **"Custom Text Display"**
4. Enter your text (max 20 characters)
5. Tap **"Build Demo App"**

**Note:** This creates a demonstration .wapp file to show the infrastructure. For a fully working app, build with the Fossil HR SDK as described above.

## Troubleshooting

### "Cannot connect to watch"
- Ensure Bluetooth is enabled
- Watch should be in pairing mode
- Try restarting both devices

### "Authentication required"
- Tap the "Authenticate" button in the Devices tab
- Make sure you've paired the watch previously
- Secret key must be configured

### "App won't install"
- Check the .wapp file is valid
- Ensure watch has enough storage
- Try disconnecting and reconnecting

### "App installed but won't run"
- Verify JerryScript version is 2.1.0
- Check firmware compatibility
- Look at debug logs for errors

## Examples to Try

### Simple Text Display

Shows text on the watch screen:

```javascript
// In your layout JSON file:
{
    "type": "text",
    "x": 120,
    "y": 120,
    "w": 200,
    "h": 50,
    "text": "Hello!",
    "size": 24,
    "align": "center"
}
```

### Button Handler

Respond to button presses:

```javascript
handler: function (event, response) {
    if (event.type === 'middle_short_press_release') {
        // Middle button tapped
        // Update display or trigger action
    } else if (event.type === 'top_short_press_release') {
        // Top button tapped
    } else if (event.type === 'bottom_short_press_release') {
        // Bottom button tapped
    }
}
```

### Timer

Start a repeating timer:

```javascript
manifest: {
    timers: ['my_timer']
},

init: function() {
    start_timer(this.node_name, 'my_timer', 1000); // 1 second
},

handler: function(event, response) {
    if (event.type === 'timer_expired' && 
        is_this_timer_expired(event, 'my_timer')) {
        // Timer fired!
        // Update display
        // Restart timer if needed
        start_timer(this.node_name, 'my_timer', 1000);
    }
}
```

## Resources

### Documentation
- [Custom Apps Guide](CUSTOM_APPS.md) - Complete documentation
- [Implementation Summary](IMPLEMENTATION_SUMMARY.md) - Technical details
- [Protocol Specification](PROTOCOL_SPECIFICATION.md) - BLE protocol

### External Resources
- [Fossil HR SDK](https://github.com/dakhnod/Fossil-HR-SDK) - Development tools
- [SDK Documentation](https://github.com/dakhnod/Fossil-HR-SDK/blob/main/DOCUMENTATION.md) - API reference
- [Gadgetbridge Apps](https://codeberg.org/Freeyourgadget/fossil-hr-gbapps) - Example apps
- [JerryScript Docs](https://jerryscript.net/) - JavaScript engine

### Community
- [Gadgetbridge Discussions](https://github.com/Freeyourgadget/Gadgetbridge/discussions)
- [r/FossilHybrids](https://www.reddit.com/r/FossilHybrids/)

## Next Steps

1. **Try installing a pre-built app** - Get familiar with the process
2. **Study example apps** - See how they work
3. **Modify an example** - Change text or behavior
4. **Build your own** - Create something unique!
5. **Share it** - Contribute to the community

Happy app building! 🎉
