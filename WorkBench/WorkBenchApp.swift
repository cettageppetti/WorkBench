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
            contentRect: NSRect(x: 0, y: 0, width: 1800, height: 900),
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
    @State private var aeroSpaceSettingsModel: AeroSpaceSettingsModel

    init() {
#if DEBUG
        if let testModel = UITestModelFactory.makeIfRequested() {
            _model = State(initialValue: testModel)
            _aeroSpaceSettingsModel = State(initialValue: UITestModelFactory.makeSettingsModel())
            return
        }
#endif
        _model = State(initialValue: WorkBenchApplicationModel())
        _aeroSpaceSettingsModel = State(initialValue: AeroSpaceSettingsModel())
    }

    var body: some Scene {
        Window("WorkBench", id: "main") {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Open Project") {
                    Task { await model.openSelectedProject() }
                }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.workflow?.draft == nil || model.isOpeningProject)
                Button("Save", action: model.save)
                    .keyboardShortcut("s", modifiers: .command)
                Button("Reload Projects", action: model.reload)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Reveal Project Library", action: model.revealProjectLibrary)
            }
        }
        Settings {
            AeroSpaceSettingsView(model: aeroSpaceSettingsModel)
        }
    }
}
