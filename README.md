# BlueShooth

A macOS menu bar app that gives you control over which Bluetooth devices can auto-connect. Prevent unwanted automatic Bluetooth connections while keeping your devices paired.

## Problem

macOS automatically connects to paired Bluetooth devices when they're in range, which can be annoying when:
- You have multiple Bluetooth speakers/headphones and only want to connect to specific ones
- You want devices paired but not automatically connecting
- You need more granular control over Bluetooth behavior

## Solution

BlueShooth runs in your menu bar and lets you choose which paired devices should NOT auto-connect. Selected devices stay paired but are disconnected when they try to connect on their own. You can still connect them whenever you want, from the BlueShooth menu or from System Settings.

## Features

- 🎯 **Selective Auto-Connect Control**: Choose which devices can auto-connect
- 🔌 **Quick Connect/Disconnect**: Connect or disconnect devices directly from the menu bar
- 🟢 **Real-Time Status**: See which devices are currently connected
- 🔋 **Battery Levels**: See battery percentages for connected devices that report them
- 🚫 **Automatic Blocking**: Disconnects blocked devices when they try to auto-connect, while letting your manual connections through
- 🙈 **Hide Devices**: Remove clutter from the list, such as hidden system pairings
- ⚙️ **Bluetooth Settings Link**: Open the native Bluetooth settings, so BlueShooth can replace the system Bluetooth menu bar item
- 🚀 **Launch at Login**: Start automatically when you log in
- 🔔 **Notifications**: Get notified about connection events
- 💾 **Persistent Settings**: Your preferences are saved between sessions
- 🔒 **Privacy-Focused**: All settings stored locally, no data collection

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 14.0 or later (for building from source)

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/tockv/blueshooth.git
   cd blueshooth
   ```

2. Build a Release copy and install it to `/Applications`:
   ```bash
   xcodebuild -scheme BlueShooth -configuration Release -derivedDataPath build build
   ditto build/Build/Products/Release/BlueShooth.app /Applications/BlueShooth.app
   open /Applications/BlueShooth.app
   ```
   Without `-derivedDataPath build`, Xcode puts the app under `~/Library/Developer/Xcode/DerivedData/` instead.

3. Click the menu bar icon and choose **Launch at Login** to start BlueShooth automatically.

4. *(Optional)* Hide the system Bluetooth menu bar item in System Settings → Menu Bar (or Control Center on older macOS) → Bluetooth → **Don't Show in Menu Bar**. Use **Bluetooth Settings…** in BlueShooth to reach the native settings.

To update, quit BlueShooth and repeat step 2.

### Code signing

With no development team set, Xcode signs the app ad-hoc ("Sign to Run Locally"). That's fine for running on your own Mac, but each rebuild looks like a new app to macOS, so after an update you may be asked for Bluetooth permission again and may need to re-enable Launch at Login. Setting a `DEVELOPMENT_TEAM` in the project gives a stable identity if this becomes annoying.

## Usage

1. **View Devices**: Click the menu bar icon (a Bluetooth antenna) to see your paired devices. The indicator beside each device shows its status:
   - Filled circle = connected
   - Outline circle = disconnected

   Connected devices that report a battery level show it in a column on the right.

2. **Connect/Disconnect**: Open a device's submenu and choose **Connect** or **Disconnect**. Connecting can take several seconds, during which the menu is unresponsive.

3. **Toggle Auto-Connect**: In the device submenu, click the auto-connect option:
   - ✅ Auto-connect: Enabled = normal macOS behavior
   - 🚫 Auto-connect: Disabled = the device is disconnected when it tries to connect on its own

   Turning auto-connect off also disconnects the device if it's currently connected.

4. **Hide Devices**: Choose **Hide from List** in a device's submenu. Hidden devices appear under **Hidden Devices**, where you can show them again. Hiding only affects the list; a hidden device's auto-connect setting still applies.

5. **Other options**:
   - **Refresh Devices** re-reads the paired device list (this also happens each time the menu opens)
   - **Bluetooth Settings…** opens System Settings → Bluetooth
   - **Launch at Login** toggles starting at login; if macOS needs you to approve it, the item says so and opens Login Items settings

## How It Works

1. Lists paired devices via IOBluetooth, rebuilding the menu each time it opens
2. Registers for IOBluetooth connect notifications
3. When a device with auto-connect disabled connects, checks who started the connection:
   - **Started by the device** (`isIncoming`) → treated as an auto-connect and disconnected
   - **Started by the Mac** (the BlueShooth menu or System Settings) → treated as manual and left alone
4. Reads battery levels for connected devices (see [Battery Levels](#battery-levels))
5. Stores auto-connect and hidden-device preferences locally using UserDefaults
6. Registers as a login item via `SMAppService`

### Battery Levels

There's no single public API for Bluetooth accessory battery levels, so BlueShooth uses two sources:

- **Bluetooth Low Energy devices** (e.g. most modern mice): the standard Battery Service, read via CoreBluetooth. BlueShooth briefly opens its own connection to read the level, then closes it; the system's connection is unaffected.
- **Classic audio devices** (e.g. headphones): an undocumented `IOBluetoothDevice` property (`batteryPercentSingle`). BlueShooth checks it exists before reading, so if a future macOS removes it, these devices simply show no level. In a long-running process this value drops to 0 whenever the level changes, so BlueShooth reads it in a short-lived copy of itself (`BlueShooth --print-classic-battery`), which takes about 0.1 seconds.

Levels are read in the background at launch, every 2 minutes, and when the menu opens (Low Energy devices at most once a minute each), and the menu shows the latest reading. Classic keyboards and other devices that report battery only to macOS itself show no level, matching the native Bluetooth menu.

## Permissions

BlueShooth requires Bluetooth access to list paired devices, monitor connection events, and connect/disconnect devices. It also asks for permission to show notifications. Both are requested on first launch.

## Limitations

- Blocking happens after the connection is made: a blocked device connects briefly before being disconnected
- Connections started from the device itself (for example pressing a speaker's Bluetooth button) are treated as auto-connects and blocked
- If macOS itself reconnects to a device (rather than the device reconnecting), the connection looks manual and isn't blocked
- Devices must remain paired (unpaired devices can't be managed)
- Some Bluetooth devices may not support programmatic connection/disconnection
- `IOBluetoothDevice.pairedDevices()` can include pairings that System Settings hides; use **Hide from List** for these
- CoreBluetooth doesn't expose device addresses, so Low Energy battery levels are matched to devices by name; devices with identical names may share a reading

## Troubleshooting

Connect, block, and battery events are logged under the `com.blueshooth.app` subsystem. Stream them while reproducing a problem:

```bash
/usr/bin/log stream --style compact --predicate 'subsystem == "com.blueshooth.app"'
```

Use the full `/usr/bin/log` path in zsh, where `log` is a shell built-in.

## Development

### Project Structure

```
BlueShooth/
├── BlueShooth/
│   ├── AppDelegate.swift           # App entry point and menu bar interface
│   ├── BluetoothManager.swift      # Bluetooth device management and blocking
│   ├── BatteryMonitor.swift        # Battery level reading
│   ├── Info.plist                  # App configuration
│   └── BlueShooth.entitlements     # Required permissions
├── BlueShooth.xcodeproj/           # Xcode project
└── README.md
```

The app has no storyboard or nib, so `AppDelegate` provides its own `main()` to set itself as the application delegate.

### Technologies Used

- **Swift 5**
- **IOBluetooth**: device listing, connection control, and connect notifications
- **CoreBluetooth**: battery levels for Low Energy devices
- **AppKit**: `NSStatusBar` menu bar integration
- **ServiceManagement**: Launch at Login
- **UserNotifications**: connection event notifications

## Known Issues

- Device names may not always display correctly if the Bluetooth device doesn't provide one
- Some Bluetooth devices may not respect disconnection commands
- The app runs as a menu bar utility (no dock icon)

## Roadmap

- [x] Quick connect/disconnect from menu bar
- [x] Launch at login option
- [x] Hide devices from the list
- [x] Battery level indicators for devices
- [ ] Connect without blocking the menu
- [ ] Add device grouping/favorites
- [ ] Customize notification sounds
- [ ] Schedule-based auto-connect rules
- [ ] Connection history tracking

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Forked from the original BlueShooth project
- Built with Apple's IOBluetooth framework

## Support

If you encounter any issues or have suggestions, open an issue on [GitHub Issues](https://github.com/tockv/blueshooth/issues).
