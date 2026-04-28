// CLIOutputParser.swift
// Pure static parsing of Zephyr Shell CLI output from the GuitarAcc basestation.
// No serial port dependencies — all functions take a plain String and return structured values.

import Foundation

struct CLIOutputParser {

    // MARK: - ANSI

    /// Strip ANSI escape sequences (e.g. ESC[1;32m, ESC[m) from raw serial output.
    static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    // MARK: - Status

    struct StatusInfo {
        /// Flash config area currently in use: "A" or "B".
        let configArea: String?
        /// Sequence number from "Config area: A (seq=1)".
        let configAreaSeq: Int?
        let connectedDevices: Int?
        /// nil if the MIDI output line is absent from the response.
        let midiOutputActive: Bool?
    }

    /// Parse output of the `status` command.
    static func parseStatus(_ raw: String) -> StatusInfo {
        let text = stripANSI(raw)
        var configArea: String?
        var configAreaSeq: Int?
        var connectedDevices: Int?
        var midiOutputActive: Bool?

        for line in text.components(separatedBy: .newlines) {
            // "Config area: A (seq=1)"
            if configArea == nil,
               let r = line.range(of: #"(?i)config\s+area\s*:\s*([A-Za-z])"#, options: .regularExpression) {
                let m = String(line[r])
                if let lr = m.range(of: #"[A-Za-z]$"#, options: .regularExpression) {
                    configArea = String(m[lr]).uppercased()
                }
            }
            if configAreaSeq == nil,
               let r = line.range(of: #"seq\s*=\s*(\d+)"#, options: .regularExpression) {
                let m = String(line[r])
                if let nr = m.range(of: #"\d+"#, options: .regularExpression) {
                    configAreaSeq = Int(m[nr])
                }
            }
            // "Connected devices: 0"
            if connectedDevices == nil,
               let r = line.range(of: #"(?i)connected\s+devices\s*:\s*(\d+)"#, options: .regularExpression) {
                let m = String(line[r])
                if let nr = m.range(of: #"\d+"#, options: .regularExpression) {
                    connectedDevices = Int(m[nr])
                }
            }
            // "MIDI output: Active" / "MIDI output: Inactive"
            if midiOutputActive == nil, line.lowercased().contains("midi output") {
                midiOutputActive = line.lowercased().contains("active") && !line.lowercased().contains("inactive")
            }
        }

        return StatusInfo(
            configArea: configArea,
            configAreaSeq: configAreaSeq,
            connectedDevices: connectedDevices,
            midiOutputActive: midiOutputActive
        )
    }

    // MARK: - Topology

    struct TopoShowInfo {
        /// Number of topology instances (derived from highest instance index + 1).
        let instanceCount: Int
        /// Set of topology type codes seen (1=T1, 2=T2, 3=T3, 4=T4).
        let topoTypes: Set<Int>
        /// Mixer type code (0=PASSTHROUGH, 1=SUM, 2=AVERAGE, 3=MAX, 4=MIN). nil if not found.
        let mixerType: Int?
    }

    /// Parse output of the `topo show` command.
    static func parseTopoShow(_ raw: String) -> TopoShowInfo {
        let text = stripANSI(raw)
        var instanceIndices = Set<Int>()
        var topoTypes = Set<Int>()
        var mixerType: Int?

        for line in text.components(separatedBy: .newlines) {
            // "Instance 0: T1 (Simple Linear)"
            if let r = line.range(of: #"(?i)instance\s+(\d+)"#, options: .regularExpression) {
                let m = String(line[r])
                if let nr = m.range(of: #"\d+"#, options: .regularExpression),
                   let idx = Int(m[nr]) {
                    instanceIndices.insert(idx)
                }
            }
            // "T1", "T2", "T3", "T4"
            if let r = line.range(of: #"\bT([1-4])\b"#, options: .regularExpression) {
                let m = String(line[r])
                if let nr = m.range(of: #"[1-4]"#, options: .regularExpression),
                   let t = Int(m[nr]) {
                    topoTypes.insert(t)
                }
            }
            // "Default Mixer: 2 (...)" or "Mixer: 2" or "Mixer type: 2"
            if mixerType == nil,
               let r = line.range(of: #"(?i)mixer\s*(?:type)?\s*:\s*(\d+)"#, options: .regularExpression) {
                let m = String(line[r])
                if let nr = m.range(of: #"\d+"#, options: .regularExpression),
                   let v = Int(m[nr]), (0...4).contains(v) {
                    mixerType = v
                }
            }
        }

        let count = instanceIndices.isEmpty ? 0 : (instanceIndices.max()! + 1)
        return TopoShowInfo(instanceCount: count, topoTypes: topoTypes, mixerType: mixerType)
    }

    // MARK: - Function Unit

    struct FuncShowInfo {
        let index: Int?
        /// Raw type code from "Type: 2 (LINEAR)". 2 = LINEAR.
        let typeCode: Int?
        let enabled: Bool
        /// All parameter values from "Parameters: [-2000, 2000, 0, 127, 0, 0]".
        let parameters: [Int]

        // Convenience accessors for LINEAR mapping parameters.
        var inMin: Int?  { parameters.count >= 2 ? parameters[0] : nil }
        var inMax: Int?  { parameters.count >= 2 ? parameters[1] : nil }
        var outMin: Int? { parameters.count >= 4 ? parameters[2] : nil }
        var outMax: Int? { parameters.count >= 4 ? parameters[3] : nil }
    }

    /// Parse output of `func show <idx>`. Returns nil if the response is not a valid function unit block.
    static func parseFuncShow(_ raw: String) -> FuncShowInfo? {
        let text = stripANSI(raw)
        guard text.lowercased().contains("function unit") else { return nil }

        var index: Int?
        var typeCode: Int?
        var enabled = false
        var parameters: [Int] = []

        for line in text.components(separatedBy: .newlines) {
            // "Function Unit 0:"
            if index == nil,
               let r = line.range(of: #"(?i)function\s+unit\s+(\d+)"#, options: .regularExpression) {
                let m = String(line[r])
                if let nr = m.range(of: #"\d+"#, options: .regularExpression) {
                    index = Int(m[nr])
                }
            }
            // "  Type: 2 (LINEAR)"
            if typeCode == nil,
               let r = line.range(of: #"(?i)^\s*type\s*:\s*(\d+)"#, options: .regularExpression) {
                let m = String(line[r])
                if let nr = m.range(of: #"\d+"#, options: .regularExpression) {
                    typeCode = Int(m[nr])
                }
            }
            // "  Enabled: 1"
            if let r = line.range(of: #"(?i)^\s*enabled\s*:\s*(\d+)"#, options: .regularExpression) {
                let m = String(line[r])
                if let nr = m.range(of: #"\d+"#, options: .regularExpression) {
                    enabled = Int(m[nr]) != 0
                }
            }
            // "  Parameters: [-2000, 2000, 0, 127, 0, 0]"
            if parameters.isEmpty,
               let r = line.range(of: #"(?i)parameters\s*:\s*\[([^\]]+)\]"#, options: .regularExpression) {
                let m = String(line[r])
                if let ar = m.range(of: #"\[([^\]]+)\]"#, options: .regularExpression) {
                    let inner = String(m[ar]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    parameters = inner.split(separator: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        }

        return FuncShowInfo(index: index, typeCode: typeCode, enabled: enabled, parameters: parameters)
    }

    // MARK: - JSON Extraction

    /// Extract the outermost JSON object from raw serial output, stripping ANSI and command echo.
    static func extractJSON(from raw: String) -> String? {
        let text = stripANSI(raw)
        guard let startIdx = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var endIdx: String.Index? = nil
        var i = startIdx
        while i < text.endIndex {
            let ch = text[i]
            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 { endIdx = i; break }
            }
            text.formIndex(after: &i)
        }
        guard let endIdx else { return nil }
        return String(text[startIdx...endIdx])
    }

    // MARK: - Patch Export

    /// Parse output of `config export patch <n>` into a PatchConfig model.
    /// Returns nil if no valid JSON is found or decoding fails.
    static func parsePatchExport(from raw: String) -> PatchConfig? {
        guard let jsonStr = extractJSON(from: raw),
              let data = jsonStr.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(PatchExportEnvelope.self, from: data),
              let patch = envelope.config.patches.first else { return nil }
        return patch
    }

    // MARK: - Global Export

    /// Parsed result of `config export global` — includes both device-wide config and
    /// the envelope-level metadata added in firmware v3.
    struct GlobalExport: Equatable {
        let global: GlobalConfig
        let firmwareVersion: String?
        let patchCount: Int?
        let currentPatch: Int?
    }

    /// Parse output of `config export global` into a GlobalExport model.
    /// Returns nil if no valid JSON is found or decoding fails.
    static func parseGlobalExport(from raw: String) -> GlobalExport? {
        guard let jsonStr = extractJSON(from: raw),
              let data = jsonStr.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(GlobalExportEnvelope.self, from: data) else { return nil }
        return GlobalExport(
            global: envelope.config.global,
            firmwareVersion: envelope.firmwareVersion,
            patchCount: envelope.patchCount,
            currentPatch: envelope.currentPatch
        )
    }

    // MARK: - Topology Instances

    /// Parse `topo show` output into an array of VirtualPortConfig, one per topology instance,
    /// returned in instance-index order.
    static func parseTopoInstances(_ raw: String) -> [VirtualPortConfig] {
        let text = stripANSI(raw)
        var results: [VirtualPortConfig] = []

        var instanceIdx: Int? = nil
        var topoType: TopologyType = .t1
        var accelInputs: [Int] = []
        var functionUnits: [Int] = []
        var midiCCOutputs: [Int] = []

        func flush() {
            guard instanceIdx != nil else { return }
            results.append(VirtualPortConfig(
                topologyType: topoType,
                inputAxis1: AccelAxis(rawValue: accelInputs.count > 0 ? accelInputs[0] : 0) ?? .x,
                inputAxis2: AccelAxis(rawValue: accelInputs.count > 1 ? accelInputs[1] : 1) ?? .y,
                functionIndex1: functionUnits.count > 0 ? functionUnits[0] : 0,
                functionIndex2: functionUnits.count > 1 ? functionUnits[1] : 1,
                midiCC1: midiCCOutputs.count > 0 ? midiCCOutputs[0] : 16,
                midiCC2: midiCCOutputs.count > 1 ? midiCCOutputs[1] : 17
            ))
        }

        for line in text.components(separatedBy: .newlines) {
            // "Instance 0: T1 (Simple Linear)"
            if let r = line.range(of: #"(?i)instance\s+(\d+)"#, options: .regularExpression) {
                flush()
                instanceIdx = nil; topoType = .t1
                accelInputs = []; functionUnits = []; midiCCOutputs = []

                let m = String(line[r])
                if let nr = m.range(of: #"\d+"#, options: .regularExpression) {
                    instanceIdx = Int(m[nr])
                }
                if let tr = line.range(of: #"\bT([1-4])\b"#, options: .regularExpression) {
                    let tm = String(line[tr])
                    if let nr = tm.range(of: #"[1-4]"#, options: .regularExpression),
                       let rawType = Int(tm[nr]) {
                        topoType = TopologyType(rawValue: rawType) ?? .t1
                    }
                }
            } else if instanceIdx != nil {
                let lower = line.lowercased()
                if lower.contains("accel input") {
                    accelInputs = parseIntArray(from: line)
                } else if lower.contains("function unit") {
                    functionUnits = parseIntArray(from: line)
                } else if lower.contains("midi cc") {
                    midiCCOutputs = parseIntArray(from: line)
                }
            }
        }
        flush()
        return results
    }

    // MARK: - Private Helpers

    private static func parseIntArray(from line: String) -> [Int] {
        guard let r = line.range(of: #"\[([^\]]+)\]"#, options: .regularExpression) else { return [] }
        let inner = String(line[r]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return inner.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: - VirtualPortConfig derivation

    /// Convert a parsed PatchConfig into VirtualPortConfig instances ready for UI binding.
    /// Uses topology and function export data from the patch; falls back to defaults when absent.
    static func virtualPortConfigs(from patch: PatchConfig) -> [VirtualPortConfig] {
        guard let topologies = patch.topologies else { return [] }
        let functions = patch.functions ?? []

        return topologies.sorted { $0.instance < $1.instance }.map { topo in
            let funcIdx1 = topo.funcUnits.count > 0 ? topo.funcUnits[0] : 0
            let funcIdx2 = topo.funcUnits.count > 1 ? topo.funcUnits[1] : funcIdx1 + 1

            func linearParams(for unitIdx: Int) -> LinearFunctionParams {
                if let f = functions.first(where: { $0.unit == unitIdx }) {
                    return LinearFunctionParams(inputMin: f.inMin, inputMax: f.inMax,
                                               outputMin: f.outMin, outputMax: f.outMax)
                }
                return LinearFunctionParams()
            }

            return VirtualPortConfig(
                topologyType: TopologyType(rawValue: topo.topologyType) ?? .t1,
                inputAxis1:   AccelAxis(rawValue: topo.accelInputs.count > 0 ? topo.accelInputs[0] : 0) ?? .x,
                inputAxis2:   AccelAxis(rawValue: topo.accelInputs.count > 1 ? topo.accelInputs[1] : 1) ?? .y,
                functionIndex1: funcIdx1,
                functionIndex2: funcIdx2,
                midiCC1: topo.midiOutputs.count > 0 ? topo.midiOutputs[0] : 16,
                midiCC2: topo.midiOutputs.count > 1 ? topo.midiOutputs[1] : 17,
                linearParams1: linearParams(for: funcIdx1),
                linearParams2: linearParams(for: funcIdx2),
                enabled: topo.enabled
            )
        }
    }

    private struct PatchExportEnvelope: Codable {
        let version: Int
        let config: PatchExportConfig
        struct PatchExportConfig: Codable {
            let patches: [PatchConfig]
        }
    }

    private struct GlobalExportEnvelope: Codable {
        let version: Int
        let firmwareVersion: String?
        let patchCount: Int?
        let currentPatch: Int?
        let config: GlobalExportConfig
        struct GlobalExportConfig: Codable {
            let global: GlobalConfig
        }
    }
}
