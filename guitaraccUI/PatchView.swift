import SwiftUI

// MARK: - PatchView (Top-level container)
struct PatchView: View {
    @State private var selectedPatchIndex: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            PatchHeaderArea()
                .accessibilityIdentifier("PatchHeaderArea")

            PatchSelectionArea(selectedPatchIndex: $selectedPatchIndex)
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
    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Patches").font(.headline)
                Spacer()
                TextField("Search patches", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 260)
                    .accessibilityIdentifier("PatchSelectionArea.SearchField")
            }

            // Simple segmented control for 16 patches (0-15)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(0..<16, id: \.self) { idx in
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
        }
        .padding(8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Control Panel
struct ControlPanelArea: View {
    let selectedPatchIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls").font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    AccelerometerControlsSection()
                    // Future: ModulationControlsSection(), EffectsControlsSection(), etc.
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.visible)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Accelerometer Controls Section
struct AccelerometerControlsSection: View {
    // Example state for six accelerometer modules
    @State private var midiChannels: [Int] = Array(repeating: 1, count: 6)
    @State private var minValues: [Int] = Array(repeating: 0, count: 6)
    @State private var maxValues: [Int] = Array(repeating: 127, count: 6)

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { i in
                // Uses existing AccelerometerControl from "AccelerometerControl 2.swift"
                AccelerometerControl(
                    midiChannel: $midiChannels[i],
                    minValue: $minValues[i],
                    maxValue: $maxValues[i],
                    title: "Accel \(i+1)"
                )
                .accessibilityIdentifier("ControlPanelArea.AccelerometerControlsSection.AccelerometerControl.\(i)")
            }
        }
        .padding(8)
    }
}

#Preview {
    PatchView()
        .frame(width: 900, height: 600)
}
