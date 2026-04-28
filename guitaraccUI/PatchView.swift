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
    @State private var showingStatus = false
    @State private var showingGlobalSettings = false
    @State private var showingMIDIStats = false
    @State private var showingImport = false
    @State private var showingExport = false

    var body: some View {
        HStack(spacing: 8) {
            // Patch file actions
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

            Divider().frame(height: 20)

            // Device info modals
            Button { showingStatus = true } label: {
                Label("Status", systemImage: "waveform.path.ecg")
            }
            Button { showingGlobalSettings = true } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            Button { showingMIDIStats = true } label: {
                Label("MIDI Stats", systemImage: "music.quarternote.3")
            }

            Divider().frame(height: 20)

            // Config import/export — same style as Save/Load
            Button {
                showingImport = true
            } label: {
                Label("Import", systemImage: "arrow.down.doc")
            }
            Button {
                showingExport = true
            } label: {
                Label("Export", systemImage: "arrow.up.doc")
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

            Divider().frame(height: 20)

            ConnectionStatusIcon()
        }
        .padding(8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showingStatus) {
            StatusView().frame(minWidth: 400, minHeight: 300)
        }
        .sheet(isPresented: $showingGlobalSettings) {
            // Width: 3 cards × 160 + 2 gaps × 8 + 2 sides × 16 (outer padding) = 528
            GlobalSettingsView().frame(minWidth: 528, minHeight: 420)
        }
        .sheet(isPresented: $showingMIDIStats) {
            MIDIStatisticsView().frame(minWidth: 480, minHeight: 360)
        }
        .sheet(isPresented: $showingImport) {
            ConfigImportExportView().frame(minWidth: 520, minHeight: 400)
        }
        .sheet(isPresented: $showingExport) {
            ConfigImportExportView().frame(minWidth: 520, minHeight: 400)
        }
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

// MARK: - Accelerometer Controls Section
/// Displays a horizontal row of AccelerometerControl cards backed by parent-owned binding arrays.
/// `axisOffset` and `count` select which slice of the full 6-element arrays to show.
struct AccelerometerControlsSection: View {
    @Binding var scales: [Int]
    @Binding var offsets: [Int]
    var axisOffset: Int = 0
    var count: Int

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(axisOffset..<(axisOffset + count), id: \.self) { i in
                    if i < scales.count && i < offsets.count {
                        AccelerometerControl(
                            title: AccelAxis(rawValue: i)?.label ?? "Axis \(i)",
                            scale: $scales[i],
                            offset: $offsets[i]
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.visible)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
