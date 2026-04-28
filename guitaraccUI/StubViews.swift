// StubViews.swift
// Placeholder SwiftUI Views for all functional areas

import SwiftUI
import ORSSerial
import AppKit

struct StatusView: View {
    var body: some View {
        VStack {
            Text("Status & Monitoring View")
            Spacer()
        }.padding()
    }
}

struct GlobalSettingsView: View {
    @EnvironmentObject var serialManager: USBSerialManager
    @Environment(\.dismiss) private var dismiss

    @State private var editScales: [Int] = []
    @State private var editOffsets: [Int] = []
    @State private var originalScales: [Int] = []
    @State private var originalOffsets: [Int] = []
    @State private var isRefreshing = false
    @State private var isSaving = false
    @State private var saveError = false

    private var hasData: Bool { !editScales.isEmpty }
    private var accelCount: Int { min(3, editScales.count) }
    private var gyroCount: Int { max(0, editScales.count - 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Global Settings")
                    .font(.title2.bold())
                Spacer()
                if serialManager.isConnected {
                    Button {
                        isRefreshing = true
                        Task {
                            await serialManager.loadGlobalConfig()
                            isRefreshing = false
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || isSaving)
                }
            }

            Divider()

            if hasData {
                Text("Accelerometer Calibration").font(.headline)
                AccelerometerControlsSection(
                    scales: $editScales,
                    offsets: $editOffsets,
                    axisOffset: 0,
                    count: accelCount
                )

                if gyroCount > 0 {
                    Text("Gyroscope Calibration").font(.headline)
                        .padding(.top, 4)
                    AccelerometerControlsSection(
                        scales: $editScales,
                        offsets: $editOffsets,
                        axisOffset: 3,
                        count: gyroCount
                    )
                }
            } else {
                Text("No calibration data — connect a basestation to load settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if saveError {
                Text("Save failed — check connection and try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            // Done button — sends calibration to device and saves
            HStack {
                Spacer()
                Button {
                    // Skip save if nothing changed
                    guard editScales != originalScales || editOffsets != originalOffsets else {
                        dismiss()
                        return
                    }
                    isSaving = true
                    saveError = false
                    Task {
                        let ok = await serialManager.applyGlobalConfig(
                            scales: editScales,
                            offsets: editOffsets
                        )
                        isSaving = false
                        if ok {
                            dismiss()
                        } else {
                            saveError = true
                        }
                    }
                } label: {
                    if isSaving {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Saving…")
                        }
                    } else {
                        Text("Done")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasData || !serialManager.isConnected || isSaving || isRefreshing)
            }
        }
        .padding()
        .onAppear { syncFromDevice() }
        .onChange(of: serialManager.currentGlobalConfig) { _, _ in syncFromDevice() }
    }

    private func syncFromDevice() {
        guard let global = serialManager.currentGlobalConfig, !global.accelScale.isEmpty else { return }
        let scales = global.accelScale
        let offsets = global.accelOffset.count == global.accelScale.count
            ? global.accelOffset
            : Array(repeating: 0, count: global.accelScale.count)
        editScales = scales
        editOffsets = offsets
        originalScales = scales
        originalOffsets = offsets
    }
}

struct PatchConfigView: View {
    @EnvironmentObject var serialManager: USBSerialManager
    @State private var selectedPatch: Int = 0
    @State private var exportedPatchText: String = ""
    @State private var isLoading: Bool = false
    @State private var accelScales: [Int] = Array(repeating: 2000, count: 6)
    @State private var accelOffsets: [Int] = Array(repeating: 0, count: 6)
    var body: some View {
        VStack {
            Picker("Patch", selection: $selectedPatch) {
                ForEach(0..<16) { i in
                    Text("Patch \(i)").tag(i)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedPatch) { _, newValue in
                Task { @MainActor in
                    guard !isLoading else { return }
                    isLoading = true
                    defer { isLoading = false }
                    if serialManager.isConnected {
                        let text = await serialManager.selectAndExportPatch(newValue)
                        exportedPatchText = text
                    }
                }
            }
            Text("Patch Configuration View for Patch \(selectedPatch)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { i in
                        AccelerometerControl(
                            title: "Accel \(i)",
                            scale: $accelScales[i],
                            offset: $accelOffsets[i]
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 240)
            HStack {
                Button("Save / Sync Patch") {
                    Task { @MainActor in
                        let text = await serialManager.selectAndExportPatch(selectedPatch)
                        exportedPatchText = text
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!serialManager.isConnected || isLoading)

                Button("Refresh Export") {
                    Task { @MainActor in
                        let text = await serialManager.runCommandCollectingOutput("config export patch \(selectedPatch)", perLineTimeout: 0.8, maxLines: 2000)
                        exportedPatchText = text
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!serialManager.isConnected || isLoading)
            }
            ScrollView {
                Text(exportedPatchText.isEmpty ? "(No export yet)" : exportedPatchText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 260)
            .padding(.top, 4)
            Spacer()
        }.padding()
        .task {
            guard !isLoading else { return }
            isLoading = true
            defer { isLoading = false }
            guard serialManager.isConnected else { return }
            if let idx = await serialManager.queryCurrentPatchIndex() {
                selectedPatch = max(0, min(15, idx))
            } else {
                // If we can't determine, keep current selection but log it
                serialManager.log.append("Sync: using existing selected patch \(selectedPatch) (device did not report current patch)")
            }
            let text = await serialManager.runCommandCollectingOutput("config export patch \(selectedPatch)", perLineTimeout: 0.8, maxLines: 2000)
            exportedPatchText = text
        }
        .onChange(of: serialManager.isConnected) { _, connected in
            guard connected else { return }
            Task { @MainActor in
                guard !isLoading else { return }
                isLoading = true
                defer { isLoading = false }
                if let idx = await serialManager.queryCurrentPatchIndex() {
                    selectedPatch = max(0, min(15, idx))
                }
                let text = await serialManager.runCommandCollectingOutput("config export patch \(selectedPatch)", perLineTimeout: 0.8, maxLines: 2000)
                exportedPatchText = text
            }
        }
    }
}

struct MIDIStatisticsView: View {
    var body: some View {
        VStack {
            Text("MIDI Statistics & Diagnostics View")
            Spacer()
        }.padding()
    }
}

struct ConfigImportExportView: View {
    var body: some View {
        VStack {
            Text("Configuration Import/Export View")
            Spacer()
        }.padding()
    }
}

struct TerminalView: View {
    @EnvironmentObject var serialManager: USBSerialManager
    @State private var commandText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    Text(serialManager.terminalOutput.isEmpty
                         ? (serialManager.isConnected ? "Connected — type a command below." : "Not connected.")
                         : serialManager.terminalOutput)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(serialManager.terminalOutput.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)

                    // Invisible anchor at the bottom for auto-scroll
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.08))
                .onChange(of: serialManager.terminalOutput) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("Enter command…", text: $commandText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($inputFocused)
                    .onSubmit { send() }
                    .disabled(!serialManager.isConnected)

                Button("Send") { send() }
                    .disabled(commandText.isEmpty || !serialManager.isConnected)

                Divider().frame(height: 20)

                Button {
                    serialManager.clearTerminalOutput()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear terminal output")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .onAppear { inputFocused = true }
    }

    private func send() {
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        serialManager.sendRawCommand(cmd)
        commandText = ""
    }
}

struct CLIInteractionPanel: View {
    @EnvironmentObject var serialManager: USBSerialManager
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CLI Interaction Display").font(.headline)
                Spacer()
                Button {
                    let all = serialManager.log.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(all, forType: .string)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy all CLI output to clipboard")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(serialManager.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
        }
        .padding(8)
        .background(.ultraThickMaterial)
        .cornerRadius(12)
        .shadow(radius: 4)
        .frame(maxWidth: 360)
        .padding()
    }
}

struct ConnectionStatusIcon: View {
    @EnvironmentObject var serialManager: USBSerialManager
    @State private var isConnecting = false

    var body: some View {
        Button {
            if serialManager.isConnected {
                serialManager.connectedPort?.close()
            } else {
                isConnecting = true
                Task {
                    await serialManager.autoConnectCLI()
                    isConnecting = false
                }
            }
        } label: {
            ZStack {
                if isConnecting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: serialManager.isConnected ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(serialManager.isConnected ? .green : .secondary)
                        .imageScale(.large)
                }
            }
            .frame(width: 24, height: 24)
            .padding(8)
            .background(.ultraThickMaterial)
            .clipShape(Circle())
            .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
        .help(isConnecting ? "Connecting…" : serialManager.isConnected ? "Connected\(serialManager.connectedPort.map { " to \($0.path)" } ?? "") — click to disconnect" : "Not connected — click to connect")
    }
}
