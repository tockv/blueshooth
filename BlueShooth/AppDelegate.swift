import Cocoa
import IOBluetooth
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "BlueShooth")

        bluetoothManager = BluetoothManager()

        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Rebuild on every open so connection status is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        bluetoothManager.refreshDevices()
        setupMenu()
    }

    func setupMenu() {
        menu.removeAllItems()

        // Title
        let titleItem = NSMenuItem(title: "BlueShooth - Smart Bluetooth Manager", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        // Paired devices section
        let pairedDevices = bluetoothManager.getPairedDevices()

        if pairedDevices.isEmpty {
            let emptyTitle = bluetoothManager.getHiddenDevices().isEmpty ? "No paired devices found" : "All devices hidden"
            let noDevicesItem = NSMenuItem(title: emptyTitle, action: nil, keyEquivalent: "")
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

                deviceSubmenu.addItem(NSMenuItem.separator())
                let hideItem = NSMenuItem(title: "Hide from List", action: #selector(hideDevice(_:)), keyEquivalent: "")
                hideItem.target = self
                hideItem.representedObject = device
                deviceSubmenu.addItem(hideItem)

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

        let refreshItem = NSMenuItem(title: "Refresh Devices", action: #selector(refreshDevices), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let hiddenDevices = bluetoothManager.getHiddenDevices()
        if !hiddenDevices.isEmpty {
            let hiddenItem = NSMenuItem(title: "Hidden Devices", action: nil, keyEquivalent: "")
            let hiddenSubmenu = NSMenu()
            for device in hiddenDevices {
                // Hidden devices are still blocked, so flag it to explain any "Blocked" notifications.
                let suffix = bluetoothManager.isAutoConnectDisabled(for: device) ? " (auto-connect off)" : ""
                let showItem = NSMenuItem(title: "Show \(device.name)\(suffix)", action: #selector(showDevice(_:)), keyEquivalent: "")
                showItem.target = self
                showItem.representedObject = device
                hiddenSubmenu.addItem(showItem)
            }
            hiddenItem.submenu = hiddenSubmenu
            menu.addItem(hiddenItem)
        }

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem.state = .on
        case .requiresApproval:
            loginItem.state = .mixed
            loginItem.title = "Launch at Login (needs approval)"
        default:
            loginItem.state = .off
        }
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit BlueShooth", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc func connectDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? BluetoothDevice else { return }
        _ = bluetoothManager.connectDevice(device)
    }

    @objc func disconnectDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? BluetoothDevice else { return }
        _ = bluetoothManager.disconnectDevice(device)
    }

    @objc func toggleDeviceAutoConnect(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? BluetoothDevice else { return }
        bluetoothManager.toggleAutoConnect(for: device)
    }

    @objc func refreshDevices() {
        bluetoothManager.refreshDevices()
    }

    @objc func hideDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? BluetoothDevice else { return }
        bluetoothManager.setHidden(true, for: device)
    }

    @objc func showDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? BluetoothDevice else { return }
        bluetoothManager.setHidden(false, for: device)
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            NSApp.activate(ignoringOtherApps: true)  // menu bar apps aren't frontmost, so the alert would open behind other windows
            alert.runModal()
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
