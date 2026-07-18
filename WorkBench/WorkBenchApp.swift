import AppKit
import SwiftUI

@MainActor
final class WorkBenchAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: WorkBenchApplicationModel?
#if DEBUG
    private var uiTestWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model = UITestModelFactory.makeIfRequested() else { return }

        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WorkBench"
        window.center()
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.makeKeyAndOrderFront(nil)
        uiTestWindow = window
        NSApplication.shared.activate()
    }
#endif

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.applicationShouldTerminate() ?? .terminateNow
    }
}

@main
struct WorkBenchApp: App {
    @NSApplicationDelegateAdaptor(WorkBenchAppDelegate.self) private var appDelegate
    @State private var model: WorkBenchApplicationModel

    init() {
#if DEBUG
        if let testModel = UITestModelFactory.makeIfRequested() {
            _model = State(initialValue: testModel)
            return
        }
#endif
        _model = State(initialValue: WorkBenchApplicationModel())
    }

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
