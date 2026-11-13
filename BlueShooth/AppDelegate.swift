import Cocoa
import IOBluetooth
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var bluetoothManager: BluetoothManager!
    var batteryMonitor: BatteryMonitor!

    private static let instance = AppDelegate()

    private static let connectedImage = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Connected")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .regular))
    private static let disconnectedImage = NSImage(systemSymbolName: "circle", accessibilityDescription: "Disconnected")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .regular))

    // The default @main entry only wires up the delegate via a MainMenu nib, which this app doesn't have.
    @MainActor static func main() {
        if CommandLine.arguments.contains(BatteryMonitor.classicHelperArgument) {
            BatteryMonitor.printClassicLevels()  // helper mode: see BatteryMonitor.refreshClassic()
            exit(0)
        }
        let app = NSApplication.shared
        app.delegate = instance
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "BlueShooth")

        bluetoothManager = BluetoothManager()
        batteryMonitor = BatteryMonitor()
        bluetoothManager.willDisconnect = { [weak batteryMonitor] in
            batteryMonitor?.cancelAllReads()
        }

        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Rebuild on every open so connection status is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        bluetoothManager.refreshDevices()
        batteryMonitor.refresh()  // async; this open shows the last reading
        setupMenu()
    }

    /// Right-aligns battery levels in one column, clear of every device name (not just ones with a reading)
    /// so the column doesn't overlap long names or shift as devices connect.
    private func applyBatteryColumn(_ rows: [(item: NSMenuItem, name: String, battery: Int)], deviceItems: [NSMenuItem]) {
        guard !rows.isEmpty else { return }
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }

        let deviceIDs = Set(deviceItems.map { ObjectIdentifier($0) })
        let widestOther = menu.items.filter { !deviceIDs.contains(ObjectIdentifier($0)) }.map { width($0.title) }.max() ?? 0
        let widestBatteryRow = (deviceItems.map { width($0.title) }.max() ?? 0) + 16 + width("100%")
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: ceil(max(widestOther, widestBatteryRow)))]

        for row in rows {
            let title = NSMutableAttributedString(string: row.name, attributes: [.font: font, .paragraphStyle: style])
            title.append(NSAttributedString(
                string: "\t\(row.battery)%",
                attributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.secondaryLabelColor]
            ))
            row.item.attributedTitle = title
        }
    }

    func setupMenu() {
        menu.removeAllItems()
        var batteryRows: [(item: NSMenuItem, name: String, battery: Int)] = []
        var deviceItems: [NSMenuItem] = []

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
                deviceSubmenu.showsStateColumn = false
                let isConnected = bluetoothManager.isConnected(device)

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
                    title: autoConnectDisabled ? "🚫 Auto-connect: Disabled" : "✅ Auto-connect: Enabled",
                    action: #selector(toggleDeviceAutoConnect(_:)),
                    keyEquivalent: ""
                )
                autoConnectItem.target = self
                autoConnectItem.representedObject = device
                deviceSubmenu.addItem(autoConnectItem)

                deviceSubmenu.addItem(NSMenuItem.separator())
                let hideItem = NSMenuItem(title: "Hide from List", action: #selector(hideDevice(_:)), keyEquivalent: "")
                hideItem.target = self
                hideItem.representedObject = device
                deviceSubmenu.addItem(hideItem)

                // Set the submenu
                deviceItem.submenu = deviceSubmenu

                // Connection status shown in the state column, in place of the checkmark
                deviceItem.onStateImage = Self.connectedImage
                deviceItem.offStateImage = Self.disconnectedImage
                deviceItem.state = isConnected ? .on : .off
                if isConnected, let battery = batteryMonitor.level(for: device) {
                    batteryRows.append((deviceItem, device.name, battery))
                }

                menu.addItem(deviceItem)
                deviceItems.append(deviceItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh Devices", action: #selector(refreshDevices), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let hiddenDevices = bluetoothManager.getHiddenDevices()
        if !hiddenDevices.isEmpty {
            let hiddenItem = NSMenuItem(title: "Hidden Devices", action: nil, keyEquivalent: "")
            let hiddenSubmenu = NSMenu()
            hiddenSubmenu.showsStateColumn = false
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

        let settingsItem = NSMenuItem(title: "Bluetooth Settings…", action: #selector(openBluetoothSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

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

        let quitItem = NSMenuItem(title: "Quit BlueShooth", action: #selector(quitApp), keyEquivalent: "")  // no shortcuts: they'd reserve a column that pushes the battery levels away from the chevrons
        quitItem.target = self
        menu.addItem(quitItem)

        applyBatteryColumn(batteryRows, deviceItems: deviceItems)  // after all items exist, so the column can clear the widest title
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

    @objc func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
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
