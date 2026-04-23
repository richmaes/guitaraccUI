// VirtualPortControl.swift
// Mixer-strip style control for a single virtual port topology instance.
// Reuses MIDIKnob from AccelerometerControl 2.swift.

import SwiftUI

// MARK: - Data Model

/// Topology type matching firmware T1–T4.
enum TopologyType: Int, CaseIterable, Identifiable {
    case t1 = 1 // single input -> function -> single output
    case t2 = 2 // dual inputs merged -> function -> single output
    case t3 = 3 // single input -> function -> dual outputs
    case t4 = 4 // dual inputs -> dual functions -> dual outputs

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .t1: return "T1"
        case .t2: return "T2"
        case .t3: return "T3"
        case .t4: return "T4"
        }
    }

    var summary: String {
        switch self {
        case .t1: return "1-in 1-out"
        case .t2: return "2-in 1-out"
        case .t3: return "1-in 2-out"
        case .t4: return "2-in 2-out"
        }
    }

    var dualInput: Bool { self == .t2 || self == .t4 }
    var dualOutput: Bool { self == .t3 || self == .t4 }
    var dualFunction: Bool { self == .t4 }
}

/// Accelerometer / gyro axis source.
enum AccelAxis: Int, CaseIterable, Identifiable {
    case x = 0, y = 1, z = 2, roll = 3, pitch = 4, yaw = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        case .roll: return "Roll"
        case .pitch: return "Pitch"
        case .yaw: return "Yaw"
        }
    }
}

/// Mixer type for multi-input topologies (T2/T4).
enum MixerType: Int, CaseIterable, Identifiable {
    case passthrough = 0
    case sum = 1
    case average = 2
    case max = 3
    case min = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .passthrough: return "Pass"
        case .sum: return "Sum"
        case .average: return "Avg"
        case .max: return "Max"
        case .min: return "Min"
        }
    }
}

/// Linear function unit parameters.
struct LinearFunctionParams: Equatable {
    var inputMin: Int = -2000
    var inputMax: Int = 2000
    var outputMin: Int = 0
    var outputMax: Int = 127
}

/// Complete state for one virtual port topology instance.
struct VirtualPortConfig: Equatable {
    var topologyType: TopologyType = .t1
    var inputAxis1: AccelAxis = .x
    var inputAxis2: AccelAxis = .y       // used by T2/T4
    var functionIndex1: Int = 0          // 0-7
    var functionIndex2: Int = 1          // used by T4
    var midiCC1: Int = 16               // 0-127
    var midiCC2: Int = 17               // used by T3/T4
    var linearParams1: LinearFunctionParams = .init()
    var linearParams2: LinearFunctionParams = .init() // used by T4
    var enabled: Bool = true
}

// MARK: - VirtualPortControl (Mixer Strip)

/// A vertical mixer-strip control for one topology instance.
/// Displays signal flow top-to-bottom: Input -> Topology -> Function -> Output.
struct VirtualPortControl: View {
    @Binding var config: VirtualPortConfig
    var instanceIndex: Int
    var mixerType: Binding<MixerType>? // per-patch, shown only on dual-input types

    var body: some View {
        VStack(spacing: 0) {
            // -- Strip Header --
            stripHeader

            Divider().padding(.horizontal, 4)

            // -- Input Section --
            inputSection

            Divider().padding(.horizontal, 4)

            // -- Topology & Mixer --
            topologySection

            Divider().padding(.horizontal, 4)

            // -- Function Unit Section --
            functionSection

            Divider().padding(.horizontal, 4)

            // -- Output Section --
            outputSection
        }
        .padding(.vertical, 8)
        .frame(width: 160)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(config.enabled ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1.5)
        )
        .opacity(config.enabled ? 1.0 : 0.5)
        .accessibilityIdentifier("VirtualPortControl.\(instanceIndex)")
    }

    // MARK: - Strip Header

    private var stripHeader: some View {
        HStack {
            Text("VP \(instanceIndex)")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Toggle("", isOn: $config.enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 6) {
            SectionLabel("INPUT")

            Picker("Axis", selection: $config.inputAxis1) {
                ForEach(AccelAxis.allCases) { axis in
                    Text(axis.label).tag(axis)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 140)
            .accessibilityIdentifier("VirtualPortControl.\(instanceIndex).InputAxis1")

            if config.topologyType.dualInput {
                Picker("Axis 2", selection: $config.inputAxis2) {
                    ForEach(AccelAxis.allCases) { axis in
                        Text(axis.label).tag(axis)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
                .accessibilityIdentifier("VirtualPortControl.\(instanceIndex).InputAxis2")

                // Mixer type (only relevant for dual-input)
                if let mixer = mixerType {
                    Picker("Mix", selection: mixer) {
                        ForEach(MixerType.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 140)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Topology Section

    private var topologySection: some View {
        VStack(spacing: 6) {
            SectionLabel("TOPOLOGY")

            Picker("Type", selection: $config.topologyType) {
                ForEach(TopologyType.allCases) { t in
                    Text("\(t.label) \(t.summary)").tag(t)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 140)

            Text(config.topologyType.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Function Unit Section

    private var functionSection: some View {
        VStack(spacing: 6) {
            SectionLabel("FUNCTION")

            Picker("Func", selection: $config.functionIndex1) {
                ForEach(0..<8, id: \.self) { i in
                    Text("F\(i)").tag(i)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 140)

            // Linear mapping knobs for function 1
            HStack(spacing: 8) {
                MIDIKnob(value: $config.linearParams1.outputMin, label: "Out Min", size: 52)
                MIDIKnob(value: $config.linearParams1.outputMax, label: "Out Max", size: 52)
            }

            if config.topologyType.dualFunction {
                Divider().padding(.horizontal, 12)

                Picker("Func 2", selection: $config.functionIndex2) {
                    ForEach(0..<8, id: \.self) { i in
                        Text("F\(i)").tag(i)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)

                HStack(spacing: 8) {
                    MIDIKnob(value: $config.linearParams2.outputMin, label: "Out Min", size: 52)
                    MIDIKnob(value: $config.linearParams2.outputMax, label: "Out Max", size: 52)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(spacing: 6) {
            SectionLabel("OUTPUT")

            HStack(spacing: 4) {
                Text("CC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("CC", value: $config.midiCC1, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("VirtualPortControl.\(instanceIndex).CC1")
            }

            if config.topologyType.dualOutput {
                HStack(spacing: 4) {
                    Text("CC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("CC 2", value: $config.midiCC2, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("VirtualPortControl.\(instanceIndex).CC2")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// MARK: - Section Label Helper

private struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - VirtualPortStripArray (6 instances in a horizontal row)

/// Displays all 6 virtual port topology instances as a horizontal mixer strip array.
struct VirtualPortStripArray: View {
    @Binding var configs: [VirtualPortConfig]
    @Binding var mixerType: MixerType

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<configs.count, id: \.self) { i in
                VirtualPortControl(
                    config: $configs[i],
                    instanceIndex: i,
                    mixerType: $mixerType
                )
            }
        }
        .padding(8)
    }
}

// MARK: - Preview

#Preview {
    ScrollView(.horizontal) {
        VirtualPortStripArray(
            configs: .constant([
                VirtualPortConfig(topologyType: .t1, inputAxis1: .x, midiCC1: 16),
                VirtualPortConfig(topologyType: .t2, inputAxis1: .x, inputAxis2: .y, midiCC1: 17),
                VirtualPortConfig(topologyType: .t3, inputAxis1: .z, midiCC1: 18, midiCC2: 19),
                VirtualPortConfig(topologyType: .t4, inputAxis1: .roll, inputAxis2: .pitch, midiCC1: 20, midiCC2: 21),
                VirtualPortConfig(topologyType: .t1, inputAxis1: .yaw, midiCC1: 22, enabled: false),
                VirtualPortConfig(topologyType: .t1, inputAxis1: .x, midiCC1: 23),
            ]),
            mixerType: .constant(.average)
        )
        .padding()
    }
    .frame(width: 1100, height: 600)
}
