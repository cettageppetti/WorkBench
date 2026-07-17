import AppKit
import SwiftUI

@MainActor
final class WorkBenchAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: WorkBenchApplicationModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.applicationShouldTerminate() ?? .terminateNow
    }
}

@main
struct WorkBenchApp: App {
    @NSApplicationDelegateAdaptor(WorkBenchAppDelegate.self) private var appDelegate
    @State private var model = WorkBenchApplicationModel()

    var body: some Scene {
        Window("WorkBench", id: "main") {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save", action: model.save)
                    .keyboardShortcut("s", modifiers: .command)
                Button("Reload Configurations", action: model.reload)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
