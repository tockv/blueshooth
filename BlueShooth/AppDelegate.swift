import Cocoa
import IOBluetooth

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var bluetoothManager: BluetoothManager!

    private static let instance = AppDelegate()

    // The default @main entry only wires up the delegate via a MainMenu nib, which this app doesn't have.
    @MainActor static func main() {
        let app = NSApplication.shared
        app.delegate = instance
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "BlueShooth")
            button.action = #selector(statusBarButtonClicked)
        }

        // Initialize Bluetooth manager
        bluetoothManager = BluetoothManager()

        // Setup menu
        setupMenu()
    }

    @objc func statusBarButtonClicked() {
        setupMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func setupMenu() {
        menu = NSMenu()

        // Title
        let titleItem = NSMenuItem(title: "BlueShooth - Smart Bluetooth Manager", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        // Paired devices section
        let pairedDevices = bluetoothManager.getPairedDevices()

        if pairedDevices.isEmpty {
            let noDevicesItem = NSMenuItem(title: "No paired devices found", action: nil, keyEquivalent: "")
            noDevicesItem.isEnabled = false
            menu.addItem(noDevicesItem)
        } else {
            for device in pairedDevices {
                // Create submenu for each device
                let deviceItem = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
                let deviceSubmenu = NSMenu()

                // Connection status
                let isConnected = bluetoothManager.isConnected(device)
                let statusItem = NSMenuItem(
                    title: isConnected ? "🟢 Connected" : "⚪️ Disconnected",
                    action: nil,
                    keyEquivalent: ""
                )
                statusItem.isEnabled = false
                deviceSubmenu.addItem(statusItem)
                deviceSubmenu.addItem(NSMenuItem.separator())

                // Connect/Disconnect option
                if isConnected {
                    let disconnectItem = NSMenuItem(
                        title: "Disconnect",
                        action: #selector(disconnectDevice(_:)),
                        keyEquivalent: ""
                    )
                    disconnectItem.target = self
                    disconnectItem.representedObject = device
                    deviceSubmenu.addItem(disconnectItem)
                } else {
                    let connectItem = NSMenuItem(
                        title: "Connect",
                        action: #selector(connectDevice(_:)),
                        keyEquivalent: ""
                    )
                    connectItem.target = self
                    connectItem.representedObject = device
                    deviceSubmenu.addItem(connectItem)
                }

                deviceSubmenu.addItem(NSMenuItem.separator())

                // Auto-connect toggle
                let autoConnectDisabled = bluetoothManager.isAutoConnectDisabled(for: device)
                let autoConnectItem = NSMenuItem(
                    title: autoConnectDisabled ? "🚫 Auto-connect: Disabled" : "✓ Auto-connect: Enabled",
                    action: #selector(toggleDeviceAutoConnect(_:)),
                    keyEquivalent: ""
                )
                autoConnectItem.target = self
                autoConnectItem.representedObject = device
                autoConnectItem.state = autoConnectDisabled ? .on : .off
                deviceSubmenu.addItem(autoConnectItem)

                // Set the submenu
                deviceItem.submenu = deviceSubmenu

                // Update main item title based on connection status
                if isConnected {
                    deviceItem.title = "🟢 \(device.name)"
                } else {
                    deviceItem.title = "⚪️ \(device.name)"
                }

                menu.addItem(deviceItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Refresh
        menu.addItem(NSMenuItem(title: "Refresh Devices", action: #selector(refreshDevices), keyEquivalent: "r"))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "Quit BlueShooth", action: #selector(quitApp), keyEquivalent: "q"))
    }

    @objc func connectDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? BluetoothDevice else { return }

        _ = bluetoothManager.connectDevice(device)

        // Refresh menu after a short delay to show updated connection status
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupMenu()
        }
    }

    @objc func disconnectDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? BluetoothDevice else { return }

        _ = bluetoothManager.disconnectDevice(device)

        // Refresh menu after a short delay to show updated connection status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupMenu()
        }
    }

    @objc func toggleDeviceAutoConnect(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? BluetoothDevice else { return }

        bluetoothManager.toggleAutoConnect(for: device)
        setupMenu()
    }

    @objc func refreshDevices() {
        bluetoothManager.refreshDevices()
        setupMenu()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
