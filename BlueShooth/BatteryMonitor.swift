import CoreBluetooth
import IOBluetooth
import os

private let log = Logger(subsystem: "com.blueshooth.app", category: "battery")

/// Battery levels for connected devices: the BLE Battery Service for Low Energy devices,
/// and an undocumented IOBluetooth property for classic audio devices.
final class BatteryMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let classicBatteryKey = "batteryPercentSingle"

    private var central: CBCentralManager!
    private var leLevels: [String: Int] = [:]  // keyed by name: CoreBluetooth doesn't expose device addresses
    private var reading: [UUID: (peripheral: CBPeripheral, token: UUID)] = [:]
    private var lastRead: [UUID: Date] = [:]
    private var classicLevels: [String: Int] = [:]  // keyed by address
    private var classicHelperRunning = false
    private var timer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Latest known level, or nil if the device doesn't report one. Returns immediately; reads happen in `refresh()`.
    func level(for device: BluetoothDevice) -> Int? {
        leLevels[device.name] ?? classicLevels[device.address]
    }

    func refresh() {
        refreshClassic()
        guard central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        let connectedNames = Set(connected.compactMap(\.name))
        leLevels = leLevels.filter { connectedNames.contains($0.key) }
        let connectedIDs = Set(connected.map(\.identifier))
        lastRead = lastRead.filter { connectedIDs.contains($0.key) }

        for peripheral in connected where reading[peripheral.identifier] == nil {
            if let last = lastRead[peripheral.identifier], Date().timeIntervalSince(last) < 60 {
                continue  // avoid waking the radio on every menu open
            }
            let token = UUID()
            reading[peripheral.identifier] = (peripheral, token)
            lastRead[peripheral.identifier] = Date()  // throttle attempts, not just successes
            peripheral.delegate = self
            central.connect(peripheral)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.finishReading(peripheral, token: token)  // don't hold our connection if the read never completes
            }
        }
    }

    /// Cancel in-flight reads before any disconnect, or our pending connect could bring the link back up.
    /// Cancels all rather than matching by name, since IOBluetooth and CoreBluetooth names can differ.
    func cancelAllReads() {
        for entry in reading.values {
            finishReading(entry.peripheral)
        }
    }

    // MARK: - Classic devices

    static let classicHelperArgument = "--print-classic-battery"

    /// Runs in a short-lived copy of the app: prints "address<TAB>level" for each connected classic device.
    /// A long-running process's IOBluetoothDevice drops this value to 0 when the level changes, so it can't be read in-process.
    static func printClassicLevels() {
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] where device.isConnected() {
            // Undocumented, so check it exists: if Apple removes it, classic devices just show no level.
            guard device.responds(to: Selector(classicBatteryKey)),
                  let address = device.addressString,
                  let level = (device.value(forKey: classicBatteryKey) as? NSNumber)?.intValue,
                  level > 0, level <= 100 else { continue }
            print("\(address)\t\(level)")
        }
    }

    private func refreshClassic() {
        guard !classicHelperRunning, let executable = Bundle.main.executableURL else { return }
        classicHelperRunning = true
        let process = Process()
        process.executableURL = executable
        process.arguments = [Self.classicHelperArgument]
        let pipe = Pipe()
        process.standardOutput = pipe

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var levels: [String: Int] = [:]
            var succeeded = false
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                    if process.isRunning { process.terminate() }  // a hung helper would otherwise block all future reads
                }
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                succeeded = process.terminationStatus == 0
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: "\t")
                    if parts.count == 2, let level = Int(parts[1]) {
                        levels[String(parts[0])] = level
                    }
                }
            } catch {
                log.error("classic battery helper failed: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.classicHelperRunning = false
                guard succeeded else { return }  // keep the last good readings
                if levels != self.classicLevels {
                    log.notice("classic battery: \(levels.description, privacy: .public)")
                }
                self.classicLevels = levels
            }
        }
    }

    /// With a token, only finishes that specific read, so a stale timeout can't cancel a newer one.
    private func finishReading(_ peripheral: CBPeripheral, token: UUID? = nil) {
        guard let entry = reading[peripheral.identifier], token == nil || entry.token == token else { return }
        reading.removeValue(forKey: peripheral.identifier)
        central.cancelPeripheralConnection(peripheral)  // drops only our app's connection; the system's link stays up
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.notice("CoreBluetooth state: \(central.state.rawValue)")
        refresh()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.notice("battery connect failed: \(peripheral.name ?? "?", privacy: .public) \(String(describing: error), privacy: .public)")
        finishReading(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finishReading(peripheral)  // link dropped mid-read: cancel so CoreBluetooth doesn't reconnect it
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
            finishReading(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else {
            finishReading(peripheral)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer { finishReading(peripheral) }
        guard error == nil, let name = peripheral.name, let byte = characteristic.value?.first, byte <= 100 else {
            return
        }
        leLevels[name] = Int(byte)
        log.notice("battery: \(name, privacy: .public) \(byte)%")
    }
}
