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
    var body: some View {
        VStack {
            Text("Global Settings View")
            Spacer()
        }.padding()
    }
}

struct PatchConfigView: View {
    @EnvironmentObject var serialManager: USBSerialManager
    @State private var selectedPatch: Int = 0
    @State private var exportedPatchText: String = ""
    @State private var isLoading: Bool = false
    @State private var accelMidiChannels: [Int] = Array(repeating: 1, count: 6)
    @State private var accelMinValues: [Int] = Array(repeating: 0, count: 6)
    @State private var accelMaxValues: [Int] = Array(repeating: 127, count: 6)
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
                            midiChannel: $accelMidiChannels[i],
                            minValue: $accelMinValues[i],
                            maxValue: $accelMaxValues[i],
                            title: "Accel \(i+1)"
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
    var body: some View {
        VStack {
            Text("Advanced/Terminal View")
            Spacer()
        }.padding()
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
    var body: some View {
        Image(systemName: serialManager.isConnected ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.slash")
            .foregroundStyle(serialManager.isConnected ? .green : .secondary)
            .imageScale(.large)
            .padding(8)
            .background(.ultraThickMaterial)
            .clipShape(Circle())
            .shadow(radius: 2)
            .help(serialManager.isConnected ? ("Connected" + (serialManager.connectedPort?.path != nil ? " to \(serialManager.connectedPort!.path)" : "")) : "Not connected")
    }
}
