import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct AmeenMacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("Ameen Mac Cleaner") {
            ContentView()
                .environment(state)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Smart Scan") { Task { await state.smartScan() } }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Find Large Files") { state.scanLarge() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Toggle("Show Hidden Items", isOn: $state.showHidden)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
            }
        }
    }
}
