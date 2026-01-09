# Troubleshooting Guide

## Authentication Rejection (Status 0x00)

If you see authentication errors like "Authentication rejected by watch" with status code `0x00`, this means your secret key is incorrect.

### How to Extract the Correct Key from Gadgetbridge

The secret key is device-specific and stored in Gadgetbridge's SharedPreferences. Here's how to extract it:

#### Method 1: Using ADB (Recommended)

1. **Enable USB Debugging** on your Android device
2. **Connect via ADB** and extract the preferences:
   ```bash
   adb shell "run-as nodomain.freeyourgadget.gadgetbridge cat /data/data/nodomain.freeyourgadget.gadgetbridge/shared_prefs/DEVICE_[MAC_ADDRESS].xml"
   ```
   Replace `[MAC_ADDRESS]` with your watch's Bluetooth MAC address (with underscores instead of colons, e.g., `E1_23_45_67_89_AB`)

3. **Look for the authkey** in the XML output:
   ```xml
   <string name="authkey">7FAE8010D5DD74B1...</string>
   ```

4. **Copy the 32-character hex string** (without the `0x` prefix if present)

#### Method 2: Using Root Access

If you have root access on your Android device:

1. Navigate to `/data/data/nodomain.freeyourgadget.gadgetbridge/shared_prefs/`
2. Open the file `DEVICE_[MAC_ADDRESS].xml`
3. Find the `<string name="authkey">` entry
4. Copy the 32-character hex value

#### Method 3: Using Gadgetbridge Database Export

1. In Gadgetbridge, go to **Settings → Database management → Export database**
2. Extract the exported ZIP file
3. Open `gadgetbridge.db` with an SQLite viewer
4. Look in the `DEVICE_ATTRIBUTES` table for your device
5. Find the row where `key` = `authkey`
6. Copy the `value` column (should be 32 hex characters)

### Key Format Requirements

✅ **Correct format:**
- Exactly 32 hexadecimal characters (representing 16 bytes)
- Example: `7FAE8010D5DD74B19A3C2E5F68D91A4B`
- Case doesn't matter (uppercase or lowercase)
- No spaces, no `0x` prefix

❌ **Incorrect formats:**
- Too short or too long
- Contains spaces: `7F AE 80 10 ...`
- Has prefix: `0x7FAE8010...`
- Not hexadecimal characters

### Verifying Your Key

After entering your key in the app:

1. **Check the logs** for: `"Key hex: XX XX XX XX XX XX XX XX..."`
2. **Verify the first 8 bytes** match what you extracted from Gadgetbridge
3. **Ensure the device MAC address** matches your watch

### Common Causes of Authentication Rejection

| Cause | Solution |
|-------|----------|
| **Wrong key** | Re-extract the key from Gadgetbridge, ensuring you're getting it from the correct device entry |
| **Key is for different device** | Gadgetbridge may have multiple paired devices - ensure you're getting the key for the correct MAC address |
| **Watch was factory reset** | After a factory reset, the watch generates a new key. You must re-pair in Gadgetbridge to get the new key |
| **Watch paired with different phone** | Each pairing generates a unique key. Use the key from the most recent Gadgetbridge pairing |
| **Key corrupted during copy** | Ensure you copied the full 32 characters without truncation or extra characters |

### If Authentication Still Fails

If you've verified your key is correct and authentication still fails:

1. **Factory reset the watch** (this will erase all data)
2. **Re-pair with Gadgetbridge** to generate a new key
3. **Export the new key** using one of the methods above
4. **Try authenticating again** with the fresh key

### Technical Details

The authentication protocol uses:
- **AES-128-CBC encryption** with zero IV
- **Challenge-response handshake** between phone and watch
- The watch encrypts a challenge using the secret key
- Your phone must decrypt it, swap the halves, and re-encrypt
- If the watch can't decrypt your response, it rejects with status `0x00`

This means the rejection happens because the cryptographic operation fails, which is a mathematical proof that the keys don't match.

### Still Need Help?

If you've followed all these steps and authentication still fails, please file an issue with:
- Full debug logs (use the "Export Logs" feature in the app)
- First 8 bytes of your key (for verification): `7F AE 80 10 D5 DD 74 B1` (example)
- Your watch model and firmware version
- Whether the watch was ever paired with the official Fossil app
