// GuitarAccApp.swift
// Main app entry and minimal navigation between stub views

import SwiftUI
import SwiftData

@main
struct GuitarAccApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    @StateObject private var serialManager = USBSerialManager()

    var body: some Scene {
        WindowGroup {
            MainAppView()
                .environmentObject(serialManager)
        }
        .modelContainer(sharedModelContainer)
    }
}


struct MainAppView: View {
    @EnvironmentObject var serialManager: USBSerialManager
    @State private var selection: Int = 0
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Text("Status").tag(0)
                Text("Global Settings").tag(1)
                Text("Patch Config").tag(2)
                Text("MIDI Stats").tag(3)
                Text("Import/Export").tag(4)
                Text("Terminal").tag(5)
            }
            .frame(minWidth: 180)
        } detail: {
            switch selection {
            case 0: StatusView()
            case 1: GlobalSettingsView()
            case 2: PatchConfigView()
            case 3: MIDIStatisticsView()
            case 4: ConfigImportExportView()
            case 5: TerminalView()
            default: Text("Select a view")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            CLIInteractionPanel()
        }
        .overlay(alignment: .topTrailing) {
            ConnectionStatusIcon()
                .padding([.top, .trailing], 12)
        }
        .task {
            await serialManager.autoConnectCLI()
        }
    }
}

