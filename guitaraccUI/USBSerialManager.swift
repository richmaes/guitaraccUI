// USBSerialManager.swift
// Handles serial port discovery, probing, and communication for Zephyr Shell CLI

import Foundation
import SwiftUI
import ORSSerial // Ensure you add ORSSerialPort via Swift Package Manager
import Combine

@MainActor
class USBSerialManager: NSObject, ObservableObject, ORSSerialPortDelegate {
    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        // Forward to the other delegate variant to keep behavior consistent
        serialPortWasRemoved(fromSystem: serialPort)
    }
    
    @Published var availablePorts: [String] = []
    @Published var connectedPort: ORSSerialPort?
    @Published var isConnected: Bool = false
    @Published var log: [String] = []
    @Published var patchCount: Int = 0
    @Published var topologyInstanceCount: Int = 0
    @Published var functionUnitCount: Int = 0
    @Published var discoveredTopologyTypes: Set<Int> = []
    @Published var discoveredMixerType: Int = 2 // default: average
    @Published var firmwareVersion: String = ""
    @Published var capabilitiesDiscovered: Bool = false
    @Published var parsedTopologyConfigs: [VirtualPortConfig] = []
    @Published var currentPatchConfig: PatchConfig? = nil
    
    private var readBuffer = Data()
    private var pendingReadContinuation: CheckedContinuation<String, Never>?
    
    private let baudRate: Int = 115200
    private let timeout: TimeInterval = 1
    private let knownProbeCommand: String = "status\n"
    
    // Discovers all /dev/tty.usbmodem* ports
    func discoverPorts() {
        let fm = FileManager.default
        let devDir = "/dev"
        guard let contents = try? fm.contentsOfDirectory(atPath: devDir) else { return }
        let cuModem = contents.filter { $0.hasPrefix("cu.usbmodem") }.sorted().map { "/dev/" + $0 }
        let ttyModem = contents.filter { $0.hasPrefix("tty.usbmodem") }.sorted().map { "/dev/" + $0 }
        let cuSerial = contents.filter { $0.hasPrefix("cu.usbserial") || $0.hasPrefix("cu.SLAB_USBtoUART") }.sorted().map { "/dev/" + $0 }
        let ttySerial = contents.filter { $0.hasPrefix("tty.usbserial") || $0.hasPrefix("tty.SLAB_USBtoUART") }.sorted().map { "/dev/" + $0 }
        let ports = cuModem + cuSerial + ttyModem + ttySerial
        self.availablePorts = ports
        log.append("Scan: found \(ports.count) usbmodem/usbserial ports: \(ports.joined(separator: ", "))")
    }
    
    // Attempts to connect and probe each port in order, then runs capability discovery
    func autoConnectCLI() async {
        log.append("Auto-connect: scanning for CLI port…")
        discoverPorts()
        for portName in availablePorts {
            if await probePort(portName) {
                await runCapabilityDiscovery()
                return // connected
            }
        }
        // If here, none responded as CLI
        isConnected = false
        connectedPort = nil
        log.append("No valid CLI interface found.")
    }
    
    // Opens port, sends probe, checks response
    private func probePort(_ portName: String) async -> Bool {
        guard let port = ORSSerialPort(path: portName) else { return false }
        log.append("Probing port: \(portName)")
        port.baudRate = baudRate as NSNumber
        port.usesRTSCTSFlowControl = false // Enable hardware flow control
        port.delegate = self
        port.open()
        port.dtr = true
        
        try? await Task.sleep(nanoseconds: 1_500_000_000) // wait 0.3s and ignore cancellation
        if port.isOpen {
            port.send(knownProbeCommand.data(using: .utf8)!)
            let response = await readLine(from: port, timeout: timeout)
            if response.contains("GuitarAcc") || response.contains("Basestation") {
                // Detected CLI
                connectedPort = port
                isConnected = true
                log.append("Connected to CLI port: \(portName)")
                return true
            }
            log.append("Port \(portName) did not respond as CLI.")
            port.close()
        } else {
            log.append("Failed to open port: \(portName)")
        }
        return false
    }
    
    // Reads a line from the serial port using delegate buffering with timeout
    private func readLine(from port: ORSSerialPort, timeout: TimeInterval) async -> String {
        // If a read is already pending, cancel it by returning empty
        if pendingReadContinuation != nil { return "" }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            // Store continuation and clear buffer
            self.pendingReadContinuation = continuation
            self.readBuffer.removeAll(keepingCapacity: true)
            // Set up a timeout task
            let deadline = DispatchTime.now() + timeout
            DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
                guard let self else { return }
                if let cont = self.pendingReadContinuation {
                    self.pendingReadContinuation = nil
                    let str = String(data: self.readBuffer, encoding: .utf8) ?? ""
                    self.readBuffer.removeAll(keepingCapacity: true)
                    cont.resume(returning: str)
                }
            }
        }
    }
    
    // Send CLI command (appends newline)
    func sendCommand(_ command: String) {
        guard let port = connectedPort, port.isOpen else { return }
        let cmd = command.hasSuffix("\n") ? command : command + "\n"
        port.send(cmd.data(using: .utf8)!)
        log.append("> " + command)
    }
    
    // Execute a CLI command and collect output until a quiet period or newline-only response
    // This is a simple line-oriented collector with a per-line timeout.
    func runCommandCollectingOutput(_ command: String, perLineTimeout: TimeInterval = 0.5, maxLines: Int = 200) async -> String {
        guard let port = connectedPort, port.isOpen else { return "" }
        let cmd = command.hasSuffix("\n") ? command : command + "\n"
        port.send(cmd.data(using: .utf8)!)
        log.append("> " + command.trimmingCharacters(in: .whitespacesAndNewlines))
        var collected = ""
        var linesRead = 0
        while linesRead < maxLines {
            let line = await readLine(from: port, timeout: perLineTimeout)
            if line.isEmpty { break }
            collected += line
            linesRead += 1
            // Heuristic: if the device echoes prompt or we see a closing brace, we can stop early for JSON
            if line.contains("\n") && (line.contains("> ") || line.contains("}\n")) {
                // continue loop; timeout will end if no more data
            }
        }
        return collected
    }

    // Convenience: select a patch and then export its configuration
    func selectAndExportPatch(_ index: Int) async -> String {
        // First, select the patch so the basestation loads it
        _ = await runCommandCollectingOutput("config select \(index)")
        // Then, export that patch's configuration
        let exported = await runCommandCollectingOutput("config export patch \(index)", perLineTimeout: 0.8, maxLines: 2000)
        return exported
    }
    
    // Query the device for the currently selected patch index by inspecting CLI output
    func queryCurrentPatchIndex() async -> Int? {
        log.append("Sync: querying current patch index…")
        let showOut = await runCommandCollectingOutput("config show", perLineTimeout: 0.6, maxLines: 400)
        if let idx = parseFirstPatchIndex(from: showOut) {
            log.append("Sync: current patch index (from config show): \(idx)")
            return idx
        }
        let statusOut = await runCommandCollectingOutput("status", perLineTimeout: 0.6, maxLines: 200)
        if let idx = parseFirstPatchIndex(from: statusOut) {
            log.append("Sync: current patch index (from status): \(idx)")
            return idx
        }
        log.append("Sync: could not determine current patch index.")
        return nil
    }

    // Query the device for how many patches it supports via `config list`
    func queryPatchCount() async -> Int {
        let output = await runCommandCollectingOutput("config list", perLineTimeout: 0.6, maxLines: 100)
        // Count lines matching "Patch <N>" pattern
        let lines = output.components(separatedBy: .newlines)
        let count = lines.filter { line in
            line.range(of: #"\bPatch\s+\d+"#, options: .regularExpression) != nil
        }.count
        let result = max(count, 0)
        patchCount = result
        log.append("Patch count from device: \(result)")
        return result
    }

    // MARK: - Device Capability Discovery

    /// Runs the full capability discovery sequence. Call once after successful connection.
    func runCapabilityDiscovery() async {
        log.append("Discovery: starting capability discovery…")
        capabilitiesDiscovered = false

        // 1. Patch count
        _ = await queryPatchCount()

        // 2. Topology capabilities
        await queryTopologyCapabilities()

        // 3. Function unit count
        await queryFunctionUnitCount()

        // 4. Firmware version from status
        await queryFirmwareVersion()

        // 5. Load active patch config — populates topology + function data from JSON export
        await loadActivePatchConfig()

        capabilitiesDiscovered = true
        log.append("Discovery: complete — patches=\(patchCount), topo_instances=\(topologyInstanceCount), func_units=\(functionUnitCount), fw=\(firmwareVersion)")
    }

    /// Parse `topo show` to discover topology instance count, types in use, and mixer type.
    func queryTopologyCapabilities() async {
        let output = await runCommandCollectingOutput("topo show", perLineTimeout: 0.6, maxLines: 100)
        let lines = output.components(separatedBy: .newlines)

        // Count instances: lines like "Instance 0:" or "Topo[0]:" or "[0] T1" etc.
        // We look for lines that reference a topology instance index.
        var instanceIndices = Set<Int>()
        var topoTypes = Set<Int>()

        for line in lines {
            // Match instance references like "Instance 0", "Topo[0]", "[0]", "instance 0"
            if let range = line.range(of: #"(?i)(?:instance|topo)\s*\[?\s*(\d+)\s*\]?"#, options: .regularExpression) {
                let match = String(line[range])
                if let numRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    if let idx = Int(match[numRange]) {
                        instanceIndices.insert(idx)
                    }
                }
            }
            // Match topology types: "T1", "T2", "T3", "T4" or "type: 1", "type=2"
            if let range = line.range(of: #"\bT([1-4])\b"#, options: .regularExpression) {
                let match = String(line[range])
                if let numRange = match.range(of: #"[1-4]"#, options: .regularExpression) {
                    if let t = Int(match[numRange]) {
                        topoTypes.insert(t)
                    }
                }
            }
            if let range = line.range(of: #"(?i)type\s*[:=]\s*(\d+)"#, options: .regularExpression) {
                let match = String(line[range])
                if let numRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    if let t = Int(match[numRange]), (1...4).contains(t) {
                        topoTypes.insert(t)
                    }
                }
            }
            // Match mixer type: "Mixer: 2", "mixer=1", "mixer type: AVERAGE"
            if let range = line.range(of: #"(?i)mixer\s*(?:type)?\s*[:=]\s*(\d+)"#, options: .regularExpression) {
                let match = String(line[range])
                if let numRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    if let m = Int(match[numRange]), (0...4).contains(m) {
                        discoveredMixerType = m
                    }
                }
            }
        }

        if instanceIndices.isEmpty {
            // Fallback: count any lines that look like distinct instance entries
            // e.g., lines starting with "[0]", "[1]", etc.
            for line in lines {
                if let range = line.range(of: #"^\s*\[(\d+)\]"#, options: .regularExpression) {
                    let match = String(line[range])
                    if let numRange = match.range(of: #"\d+"#, options: .regularExpression) {
                        if let idx = Int(match[numRange]) {
                            instanceIndices.insert(idx)
                        }
                    }
                }
            }
        }

        topologyInstanceCount = instanceIndices.isEmpty ? 0 : (instanceIndices.max()! + 1)
        discoveredTopologyTypes = topoTypes
        parsedTopologyConfigs = CLIOutputParser.parseTopoInstances(output)

        log.append("Discovery: topology instances=\(topologyInstanceCount), types=\(topoTypes.sorted()), mixer=\(discoveredMixerType)")
    }

    /// Probe function unit indices 0-7 to find how many are valid.
    func queryFunctionUnitCount() async {
        var count = 0
        for idx in 0..<8 {
            let output = await runCommandCollectingOutput("func show \(idx)", perLineTimeout: 0.4, maxLines: 20)
            // A valid response contains function info; an error/empty means this index doesn't exist
            let lower = output.lowercased()
            if lower.contains("linear") || lower.contains("function") || lower.contains("enabled") ||
               lower.contains("in_min") || lower.contains("out_min") || lower.contains("type") {
                count = idx + 1
            } else if lower.contains("invalid") || lower.contains("error") || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Stop probing — indices beyond this are likely invalid too
                break
            } else {
                // Unknown response but not clearly an error — count it conservatively
                count = idx + 1
            }
        }
        functionUnitCount = count
        log.append("Discovery: function units=\(count)")
    }

    /// Load the active patch's full JSON export, then populate topology configs and capability counts.
    /// This supersedes the quick-probe counts from topo show / func show for the active patch.
    func loadActivePatchConfig() async {
        let idx = await queryCurrentPatchIndex() ?? 0
        log.append("Discovery: loading patch \(idx) config…")
        let raw = await selectAndExportPatch(idx)
        guard let config = CLIOutputParser.parsePatchExport(from: raw) else {
            log.append("Discovery: failed to parse patch \(idx) export.")
            return
        }
        currentPatchConfig = config
        parsedTopologyConfigs = CLIOutputParser.virtualPortConfigs(from: config)
        if let mixerType = config.defaultMixerType {
            discoveredMixerType = mixerType
        }
        if let topos = config.topologies, !topos.isEmpty {
            topologyInstanceCount = topos.count
        }
        if let funcs = config.functions, !funcs.isEmpty {
            functionUnitCount = funcs.count
        }
        log.append("Discovery: patch \(idx) loaded — \(parsedTopologyConfigs.count) topology instances, \(config.functions?.count ?? 0) function units")
    }

    /// Parse firmware version from `status` output.
    func queryFirmwareVersion() async {
        let output = await runCommandCollectingOutput("status", perLineTimeout: 0.6, maxLines: 50)
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            // Match patterns like "FW: 1.2.3", "Version: 1.0", "firmware: v2.1.0"
            if let range = line.range(of: #"(?i)(?:fw|firmware|version)\s*[:=]\s*v?(\S+)"#, options: .regularExpression) {
                let match = String(line[range])
                // Extract the version part after the colon/equals
                if let colonRange = match.range(of: #"[:=]\s*v?"#, options: .regularExpression) {
                    firmwareVersion = String(match[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    return
                }
            }
        }
        firmwareVersion = ""
    }

    // Attempts to parse a patch index from arbitrary CLI text
    private func parseFirstPatchIndex(from text: String) -> Int? {
        let patterns = [
            #"selected\s*patch\s*[:=]\s*(\d+)"#,
            #"active\s*patch\s*[:=]\s*(\d+)"#,
            #"\bpatch\s*[:=]\s*(\d+)"#,
            #"Patch\s+(\d+)"#
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                if let numRange = match.range(of: #"(\d+)"#, options: .regularExpression) {
                    let numStr = String(match[numRange])
                    if let val = Int(numStr) { return val }
                }
            }
        }
        return nil
    }

    // MARK: - ORSSerialPortDelegate

    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        // Append to buffer
        readBuffer.append(data)
        // If we have a line terminator, fulfill continuation
        if let cont = pendingReadContinuation,
           let str = String(data: readBuffer, encoding: .utf8),
           str.contains("\n") {
            pendingReadContinuation = nil
            // Extract up to the first newline
            if let range = str.range(of: "\n") {
                let line = String(str[..<range.upperBound])
                // Keep remaining data (after newline) in buffer for future reads
                let remaining = String(str[range.upperBound...])
                readBuffer = Data(remaining.utf8)
                cont.resume(returning: line)
            } else {
                // Fallback: return all
                let line = str
                readBuffer.removeAll(keepingCapacity: true)
                cont.resume(returning: line)
            }
        }
    }
    
    func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        // Optional: log port opened
        log.append("Port opened: \(serialPort.path)")
    }

    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        let nsErr = error as NSError
        log.append("Serial port error: \(nsErr.localizedDescription) (domain: \(nsErr.domain), code: \(nsErr.code))")
        if nsErr.domain == NSPOSIXErrorDomain && nsErr.code == 1 { // EPERM
            log.append("Hint: Permission denied opening \(serialPort.path). If the app is sandboxed, enable USB/Serial device entitlements. Prefer /dev/cu.* over /dev/tty.* when initiating connections.")
        }
    }

    func serialPortWasRemoved(fromSystem serialPort: ORSSerialPort) {
        // Treat removal similar to close
        if let cont = pendingReadContinuation {
            pendingReadContinuation = nil
            cont.resume(returning: "")
        }
        if connectedPort === serialPort {
            isConnected = false
            connectedPort = nil
            resetCapabilities()
            log.append("Port removed from system.")
        }
    }

    func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        // Invalidate any pending read
        if let cont = pendingReadContinuation {
            pendingReadContinuation = nil
            cont.resume(returning: "")
        }
        if connectedPort === serialPort {
            isConnected = false
            connectedPort = nil
            resetCapabilities()
            log.append("Port closed.")
        }
    }

    // MARK: - Helpers

    private func resetCapabilities() {
        patchCount = 0
        topologyInstanceCount = 0
        functionUnitCount = 0
        discoveredTopologyTypes = []
        discoveredMixerType = 2
        firmwareVersion = ""
        capabilitiesDiscovered = false
        parsedTopologyConfigs = []
        currentPatchConfig = nil
    }
}

