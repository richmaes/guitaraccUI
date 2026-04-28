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
                Text("Patch Config").tag(0)
                Text("Terminal").tag(1)
            }
            .frame(minWidth: 160)
        } detail: {
            switch selection {
            case 1: TerminalView()
            default: PatchView()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            CLIInteractionPanel()
        }
        .task {
            await serialManager.autoConnectCLI()
        }
    }
}

