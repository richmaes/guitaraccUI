// DeviceModels.swift
// Swift model types mirroring GuitarAcc basestation device state.

import Foundation

/// One topology routing instance within a patch.
/// Decoded from the "topologies" array in `config export patch <n>` JSON.
struct TopologyExport: Codable, Equatable {
    var instance: Int
    var enabled: Bool
    var topologyType: Int       // 1=T1, 2=T2, 3=T3, 4=T4
    var accelInputs: [Int]      // axis indices; second element used by T2/T4
    var funcUnits: [Int]        // function unit indices; second used by T4
    var midiOutputs: [Int]      // MIDI CC numbers; second used by T3/T4
}

/// One function unit within a patch.
/// Decoded from the "functions" array in `config export patch <n>` JSON.
struct FunctionExport: Codable, Equatable {
    var unit: Int
    var enabled: Bool
    var functionType: Int       // 2 = LINEAR
    var paramCount: Int         // number of meaningful params (4 for LINEAR)
    var params: [Int]           // e.g. [-2000, 2000, 0, 127, 0, 0]

    var inMin:  Int { params.count > 0 ? params[0] : -2000 }
    var inMax:  Int { params.count > 1 ? params[1] :  2000 }
    var outMin: Int { params.count > 2 ? params[2] :     0 }
    var outMax: Int { params.count > 3 ? params[3] :   127 }
}

/// Complete per-patch configuration decoded from `config export patch <n>` JSON.
/// Fields added in firmware v2 (defaultMixerType, topologies, functions) are optional
/// so older firmware responses still decode gracefully.
struct PatchConfig: Codable, Equatable {
    var patchNum: Int
    var patchName: String
    var ledMode: Int
    var midiDeadzone: Int
    var defaultMixerType: Int?           // v2+: mixer type for dual-input topologies (0-4)
    var topologies: [TopologyExport]?    // v2+: per-patch topology routing instances
    var functions: [FunctionExport]?     // v2+: per-patch function unit parameters
    // Note: accel_scale / accel_offset live in GlobalConfig, not per-patch.
}

/// Device-wide settings decoded from `config export global` JSON.
/// These are hardware-level constants shared across all patches.
struct GlobalConfig: Codable, Equatable {
    var defaultPatch: Int
    var midiChannel: Int
    var maxGuitars: Int
    var bleScanIntervalMs: Int
    var ledBrightness: Int
    var runningAverageEnable: Bool
    var runningAverageDepth: Int
    /// Full-scale G-force calibration per axis in milli-g (6 values: X, Y, Z, Roll, Pitch, Yaw).
    var accelScale: [Int]
    /// Center-point offset calibration per axis in milli-g (6 values).
    var accelOffset: [Int]
}
