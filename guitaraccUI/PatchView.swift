import SwiftUI

// MARK: - PatchView (Top-level container)
struct PatchView: View {
    @EnvironmentObject var serialManager: USBSerialManager
    @State private var selectedPatchIndex: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            PatchHeaderArea()
                .accessibilityIdentifier("PatchHeaderArea")

            PatchSelectionArea(
                selectedPatchIndex: $selectedPatchIndex,
                patchCount: serialManager.patchCount
            )
            .accessibilityIdentifier("PatchSelectionArea")

            // Control panel can be the primary growth area
            ScrollView(.vertical) {
                ControlPanelArea(selectedPatchIndex: selectedPatchIndex)
                    .accessibilityIdentifier("ControlPanelArea")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            .scrollIndicators(.visible)
        }
        .padding()
        .onChange(of: serialManager.isConnected) { _, connected in
            if !connected {
                selectedPatchIndex = 0
            }
        }
    }
}

// MARK: - Header
struct PatchHeaderArea: View {
    var body: some View {
        HStack(spacing: 12) {
            Button {
                // TODO: Save current patch/config action
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("PatchHeaderArea.SaveButton")

            Button {
                // TODO: Load action
            } label: {
                Label("Load", systemImage: "square.and.arrow.up")
            }

            Spacer()

            Button {
                // TODO: Undo action
            } label: {
                Label("Undo", systemImage: "arrow.uturn.left")
            }

            Button {
                // TODO: Redo action
            } label: {
                Label("Redo", systemImage: "arrow.uturn.right")
            }
        }
        .padding(8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Patch Selection
struct PatchSelectionArea: View {
    @Binding var selectedPatchIndex: Int
    var patchCount: Int
    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Patches").font(.headline)
                Spacer()
                if patchCount > 0 {
                    TextField("Search patches", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 260)
                        .accessibilityIdentifier("PatchSelectionArea.SearchField")
                }
            }

            if patchCount > 0 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(0..<patchCount, id: \.self) { idx in
                            Button(action: { selectedPatchIndex = idx }) {
                                Text("Patch \(idx)")
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedPatchIndex == idx ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
            } else {
                Text("No basestation connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .padding(8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: patchCount) { _, newCount in
            // Clamp selection if patch count shrinks or resets
            if newCount > 0 && selectedPatchIndex >= newCount {
                selectedPatchIndex = 0
            }
        }
    }
}

// MARK: - Control Panel
struct ControlPanelArea: View {
    @EnvironmentObject var serialManager: USBSerialManager
    let selectedPatchIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Virtual Port topology strips (only shown when device reports topology instances)
            if serialManager.topologyInstanceCount > 0 {
                VirtualPortControlsSection(
                    instanceCount: serialManager.topologyInstanceCount,
                    functionUnitCount: serialManager.functionUnitCount,
                    discoveredMixerType: serialManager.discoveredMixerType,
                    initialConfigs: serialManager.parsedTopologyConfigs
                )
            }
        }
    }
}

// MARK: - Virtual Port Controls Section
struct VirtualPortControlsSection: View {
    let instanceCount: Int
    let functionUnitCount: Int
    let discoveredMixerType: Int
    var initialConfigs: [VirtualPortConfig] = []

    @State private var configs: [VirtualPortConfig] = []
    @State private var mixerType: MixerType = .average

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Virtual Ports").font(.headline)
                Spacer()
                Text("\(instanceCount) instances, \(functionUnitCount) functions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                VirtualPortStripArray(
                    configs: $configs,
                    mixerType: $mixerType
                )
            }
            .scrollIndicators(.visible)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear {
            syncConfigArray()
            mixerType = MixerType(rawValue: discoveredMixerType) ?? .average
        }
        .onChange(of: instanceCount) { _, _ in syncConfigArray() }
        .onChange(of: initialConfigs) { _, _ in syncConfigArray() }
        .onChange(of: discoveredMixerType) { _, newVal in
            mixerType = MixerType(rawValue: newVal) ?? .average
        }
    }

    /// Populate configs from real device data when available, otherwise synthesize defaults.
    private func syncConfigArray() {
        let target = max(instanceCount, 0)
        // Use real device configs when they match the expected instance count.
        if !initialConfigs.isEmpty && initialConfigs.count == target {
            configs = initialConfigs
            return
        }
        if configs.count == target { return }
        if configs.count < target {
            for i in configs.count..<target {
                configs.append(VirtualPortConfig(
                    inputAxis1: AccelAxis(rawValue: i % 6) ?? .x,
                    functionIndex1: min(i, max(functionUnitCount - 1, 0)),
                    midiCC1: 16 + i
                ))
            }
        } else {
            configs = Array(configs.prefix(target))
        }
    }
}


#Preview {
    PatchView()
        .environmentObject(USBSerialManager())
        .frame(width: 900, height: 600)
}
