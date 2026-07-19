import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: WorkBenchApplicationModel

    var body: some View {
        Group {
            switch model.directoryAccess.status {
            case .unresolved:
                ProgressView("Preparing WorkBench…")
            case let .needsSelection(message):
                folderSelection(message: message)
            case .ready:
                if let workflow = model.workflow {
                    editor(workflow: workflow)
                } else {
                    ProgressView("Loading Projects…")
                }
            }
        }
        .frame(minWidth: 840, minHeight: 520)
        .background(WindowDelegateInstaller(delegate: model))
        .task {
            model.start()
            if model.shouldOfferInitialFolderSelection() {
                chooseConfigurationDirectory()
            }
        }
        .confirmationDialog(
            "Save changes before continuing?",
            isPresented: $model.showsUnsavedChangesDialog,
            titleVisibility: .visible
        ) {
            Button("Save") { model.resolveUnsavedChanges(.save) }
            Button("Discard Changes", role: .destructive) { model.resolveUnsavedChanges(.discard) }
            Button("Cancel", role: .cancel) { model.resolveUnsavedChanges(.cancel) }
        } message: {
            Text("The selected Project has unsaved changes.")
        }
        .alert(
            "Delete Project?",
            isPresented: Binding(
                get: { model.projectPendingDeletion != nil },
                set: { if !$0 { model.projectPendingDeletion = nil } }
            ),
            presenting: model.projectPendingDeletion
        ) { _ in
            Button("Delete", role: .destructive, action: model.deleteConfirmedProject)
            Button("Cancel", role: .cancel) { model.projectPendingDeletion = nil }
        } message: { project in
            Text("\"\(project.name)\" and its JSON configuration file will be deleted.")
        }
        .alert(
            "WorkBench Error",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("OK") { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "An unknown error occurred.")
        }
        .sheet(item: $model.launchReport) { report in
            LaunchReportView(report: report) { model.launchReport = nil }
        }
        .alert(
            "Couldn’t Open Project in Its Workspace",
            isPresented: Binding(
                get: { model.pendingLaunchPlacementFailure != nil },
                set: { if !$0 { model.cancelPendingProjectLaunch() } }
            )
        ) {
            Button("Open Without Placement") {
                Task { await model.openPendingProjectWithoutPlacement() }
            }
                .accessibilityIdentifier("open-without-placement-button")
            Button("Cancel", role: .cancel, action: model.cancelPendingProjectLaunch)
        } message: {
            Text(model.pendingLaunchPlacementFailure?.reason.message ?? "Workspace activation failed.")
        }
    }

    private func folderSelection(message: String?) -> some View {
        ContentUnavailableView {
            Label("Choose Configuration Folder", systemImage: "folder.badge.plus")
        } description: {
            Text(message ?? "WorkBench needs access to ~/Documents/WorkBench to store Project configurations.")
        } actions: {
            Button("Choose WorkBench Folder…", action: chooseConfigurationDirectory)
        }
    }

    private func editor(workflow: ProjectWorkflow) -> some View {
        NavigationSplitView {
            List(selection: projectSelection(workflow)) {
                Section("Projects") {
                    ForEach(workflow.projects, id: \.id) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                if !workflow.issues.isEmpty {
                    Section("Configuration Issues") {
                        ForEach(workflow.issues) { issue in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(issue.fileURL.lastPathComponent)
                                    Text(issue.message).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("projects-list")
            .navigationTitle("Projects")
        } content: {
            List(selection: $model.selectedResourceID) {
                Label("Project Settings", systemImage: "gearshape")
                    .tag(nil as ResourceID?)
                    .accessibilityIdentifier("project-settings-row")
                ForEach(workflow.draft?.resources ?? [], id: \.id) { resource in
                    Label(resource.name, systemImage: icon(for: resource.payload))
                        .tag(resource.id)
                        .foregroundStyle(isUnsupported(resource.payload) ? .secondary : .primary)
                }
                .onMove(perform: model.moveResources)
            }
            .accessibilityIdentifier("resources-list")
            .navigationTitle(workflow.draft?.name ?? "Resources")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Menu {
                        Button("Safari Window") {
                            model.addResource(.browserWindow(BrowserWindow(tabs: ["https://apple.com"])))
                        }
                        Button("Chrome Window") {
                            model.addResource(.chromeWindow(BrowserWindow(tabs: ["https://google.com"])))
                        }
                        Button("Terminal Session") {
                            model.addResource(.terminalSession(TerminalSession(workingDirectory: "~/")))
                        }
                        Button("Finder Window") {
                            model.addResource(.finderWindow(FinderWindow(folder: "~/")))
                        }
                    } label: { Label("Add Resource", systemImage: "plus") }
                    Spacer()
                    Button(action: model.removeSelectedResource) {
                        Label("Remove Resource", systemImage: "minus")
                    }
                    .disabled(model.selectedResourceID == nil)
                }
                .padding(8)
                .background(.bar)
            }
        } detail: {
            properties(workflow: workflow)
                .navigationTitle("Properties")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: model.createProject) { Label("New Project", systemImage: "plus") }
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("new-project-button")
                Button(action: model.duplicateSelectedProject) {
                    Label("Duplicate Project", systemImage: "plus.square.on.square")
                }
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("duplicate-project-button")
                .disabled(workflow.draft == nil)
                Button(action: model.confirmDeleteSelectedProject) {
                    Label("Delete Project", systemImage: "trash")
                }
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("delete-project-button")
                .disabled(workflow.draft == nil)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open Project", systemImage: "play.fill") {
                    Task { await model.openSelectedProject() }
                }
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("open-project-button")
                    .disabled(workflow.draft == nil || model.isOpeningProject)
                Button("Save", systemImage: "square.and.arrow.down", action: model.save)
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("save-project-button")
                    .disabled(!workflow.isDirty)
            }
        }
    }

    @ViewBuilder
    private func properties(workflow: ProjectWorkflow) -> some View {
        if let resourceID = model.selectedResourceID,
           let index = workflow.draft?.resources.firstIndex(where: { $0.id == resourceID }),
           let resource = workflow.draft?.resources[index] {
            Form {
                TextField("Name", text: resourceNameBinding(resourceID: resourceID, workflow: workflow))
                    .accessibilityIdentifier("resource-name-field")
                resourceFields(resource: resource, workflow: workflow)
                validationMessages(for: workflow.draft)
            }
            .formStyle(.grouped)
        } else if workflow.draft != nil {
            Form {
                TextField("Project Name", text: projectNameBinding(workflow))
                    .accessibilityIdentifier("project-name-field")
                if workflow.isDirty {
                    Label("Unsaved Changes", systemImage: "circle.fill")
                        .accessibilityIdentifier("unsaved-changes-indicator")
                        .foregroundStyle(.orange)
                }
                launchDestinationFields(workflow: workflow)
                validationMessages(for: workflow.draft)
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Project Selected", systemImage: "hammer")
        }
    }

    @ViewBuilder
    private func launchDestinationFields(workflow: ProjectWorkflow) -> some View {
        Section("Launch Destination") {
            switch workflow.draft?.launchDestination {
            case nil:
                Picker("Placement", selection: launchDestinationKindBinding(workflow)) {
                    Text("Normal Window Placement").tag(LaunchDestinationKind.none)
                    Text("AeroSpace Workspace").tag(LaunchDestinationKind.aeroSpace)
                }
                .accessibilityIdentifier("launch-destination-picker")
            case .aeroSpaceWorkspace:
                Picker("Placement", selection: launchDestinationKindBinding(workflow)) {
                    Text("Normal Window Placement").tag(LaunchDestinationKind.none)
                    Text("AeroSpace Workspace").tag(LaunchDestinationKind.aeroSpace)
                }
                .accessibilityIdentifier("launch-destination-picker")
                TextField("Workspace", text: aeroSpaceWorkspaceBinding(workflow))
                    .accessibilityIdentifier("aerospace-workspace-field")
                if !model.availableAeroSpaceWorkspaces.isEmpty {
                    Menu("Choose Available Workspace") {
                        ForEach(model.availableAeroSpaceWorkspaces, id: \.self) { workspace in
                            Button(workspace) {
                                model.updateDraft {
                                    $0.launchDestination = .aeroSpaceWorkspace(workspace)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("available-workspaces-menu")
                }
                Button(model.isDiscoveringAeroSpaceWorkspaces ? "Refreshing…" : "Refresh Workspaces") {
                    Task { await model.discoverAeroSpaceWorkspaces() }
                }
                .disabled(model.isDiscoveringAeroSpaceWorkspaces)
                .accessibilityIdentifier("refresh-workspaces-button")
                if let error = model.aeroSpaceWorkspaceDiscoveryError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            case let .unsupported(type, _):
                LabeledContent("Placement Type", value: type)
                Label(
                    "This launch destination is unsupported. Its JSON will be preserved.",
                    systemImage: "questionmark.diamond"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func validationMessages(for project: Project?) -> some View {
        if let project {
            let issues = ProjectValidator.validate(project)
            if !issues.isEmpty {
                Section("Validation") {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Label("\(issue.field): \(issue.message)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resourceFields(resource: Resource, workflow: ProjectWorkflow) -> some View {
        switch resource.payload {
        case let .browserWindow(browser):
            browserFields(browser, kind: .safari, resourceID: resource.id, workflow: workflow)
        case let .chromeWindow(browser):
            browserFields(browser, kind: .chrome, resourceID: resource.id, workflow: workflow)
        case let .terminalSession(terminal):
            TextField("Working Directory", text: payloadStringBinding(
                terminal.workingDirectory, resourceID: resource.id,
                makePayload: { .terminalSession(TerminalSession(workingDirectory: $0)) }
            ))
            .accessibilityIdentifier("terminal-working-directory-field")
        case let .finderWindow(finder):
            TextField("Folder", text: payloadStringBinding(
                finder.folder, resourceID: resource.id,
                makePayload: { .finderWindow(FinderWindow(folder: $0)) }
            ))
        case let .unsupported(type, _):
            LabeledContent("Type", value: type)
            Label("This Resource type is unsupported. Its JSON will be preserved.", systemImage: "questionmark.diamond")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func browserFields(
        _ browser: BrowserWindow,
        kind: BrowserKind,
        resourceID: ResourceID,
        workflow: ProjectWorkflow
    ) -> some View {
        Section(kind.sectionTitle) {
            ForEach(browser.tabs.indices, id: \.self) { tabIndex in
                TextField("URL", text: browserTabBinding(resourceID, tabIndex, kind, workflow))
                    .accessibilityIdentifier("browser-tab-\(tabIndex)-field")
            }
            Button("Add Tab") {
                model.updateDraft { project in
                    guard let index = project.resources.firstIndex(where: { $0.id == resourceID }),
                          var currentBrowser = kind.browser(from: project.resources[index].payload) else { return }
                    currentBrowser.tabs.append("https://")
                    project.resources[index].payload = kind.payload(currentBrowser)
                }
            }
            if browser.tabs.count > 1 {
                Button("Remove Last Tab") {
                    model.updateDraft { project in
                        guard let index = project.resources.firstIndex(where: { $0.id == resourceID }),
                              var currentBrowser = kind.browser(from: project.resources[index].payload),
                              currentBrowser.tabs.count > 1 else { return }
                        currentBrowser.tabs.removeLast()
                        project.resources[index].payload = kind.payload(currentBrowser)
                    }
                }
            }
        }
    }

    private func projectSelection(_ workflow: ProjectWorkflow) -> Binding<ProjectID?> {
        Binding(
            get: { workflow.selectedProjectID },
            set: { selection in model.selectProject(selection) }
        )
    }

    private func projectNameBinding(_ workflow: ProjectWorkflow) -> Binding<String> {
        Binding(get: { workflow.draft?.name ?? "" }, set: { name in model.updateDraft { $0.name = name } })
    }

    private func launchDestinationKindBinding(_ workflow: ProjectWorkflow) -> Binding<LaunchDestinationKind> {
        Binding(get: {
            if case .aeroSpaceWorkspace = workflow.draft?.launchDestination { .aeroSpace } else { .none }
        }, set: { kind in
            model.updateDraft { project in
                switch kind {
                case .none:
                    project.launchDestination = nil
                case .aeroSpace:
                    project.launchDestination = .aeroSpaceWorkspace("")
                }
            }
        })
    }

    private func aeroSpaceWorkspaceBinding(_ workflow: ProjectWorkflow) -> Binding<String> {
        Binding(get: {
            guard case let .aeroSpaceWorkspace(workspace) = workflow.draft?.launchDestination else {
                return ""
            }
            return workspace
        }, set: { workspace in
            model.updateDraft { $0.launchDestination = .aeroSpaceWorkspace(workspace) }
        })
    }

    private func resourceNameBinding(resourceID: ResourceID, workflow: ProjectWorkflow) -> Binding<String> {
        Binding(get: {
            workflow.draft?.resources.first(where: { $0.id == resourceID })?.name ?? ""
        }, set: { name in
            model.updateDraft { project in
                guard let index = project.resources.firstIndex(where: { $0.id == resourceID }) else { return }
                project.resources[index].name = name
            }
        })
    }

    private func browserTabBinding(
        _ resourceID: ResourceID,
        _ tabIndex: Int,
        _ kind: BrowserKind,
        _ workflow: ProjectWorkflow
    ) -> Binding<String> {
        Binding(get: {
            guard let resource = workflow.draft?.resources.first(where: { $0.id == resourceID }),
                  let browser = kind.browser(from: resource.payload),
                  browser.tabs.indices.contains(tabIndex) else { return "" }
            return browser.tabs[tabIndex]
        }, set: { value in
            model.updateDraft { project in
                guard let index = project.resources.firstIndex(where: { $0.id == resourceID }),
                      var browser = kind.browser(from: project.resources[index].payload),
                      browser.tabs.indices.contains(tabIndex) else { return }
                browser.tabs[tabIndex] = value
                project.resources[index].payload = kind.payload(browser)
            }
        })
    }

    private func payloadStringBinding(
        _ current: String,
        resourceID: ResourceID,
        makePayload: @escaping (String) -> ResourcePayload
    ) -> Binding<String> {
        Binding(get: { current }, set: { value in
            model.updateDraft { project in
                guard let index = project.resources.firstIndex(where: { $0.id == resourceID }) else { return }
                project.resources[index].payload = makePayload(value)
            }
        })
    }

    private func icon(for payload: ResourcePayload) -> String {
        switch payload {
        case .browserWindow: "safari"
        case .chromeWindow: "globe"
        case .terminalSession: "terminal"
        case .finderWindow: "folder"
        case .unsupported: "questionmark.diamond"
        }
    }

    private func isUnsupported(_ payload: ResourcePayload) -> Bool {
        if case .unsupported = payload { true } else { false }
    }

    private func chooseConfigurationDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose the WorkBench Configuration Folder"
        panel.message = "Create or select the WorkBench folder in Documents. WorkBench will remember your choice."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.selectDirectory(url)
    }
}

private enum LaunchDestinationKind: Hashable {
    case none
    case aeroSpace
}

struct AeroSpaceSettingsView: View {
    @Bindable var model: AeroSpaceSettingsModel

    var body: some View {
        Form {
            Section("AeroSpace") {
                Toggle("Enable AeroSpace integration", isOn: Binding(
                    get: { model.settings.isEnabled },
                    set: { model.setEnabled($0) }
                ))
                .accessibilityIdentifier("enable-aerospace-toggle")
                Text("WorkBench activates a Project’s configured workspace before opening its Resources.")
                    .foregroundStyle(.secondary)
                if model.settings.isEnabled {
                    Button(model.isDiscovering ? "Checking…" : "Check Connection") {
                        Task { await model.discoverWorkspaces() }
                    }
                    .disabled(model.isDiscovering)
                    if !model.workspaces.isEmpty {
                        LabeledContent("Available Workspaces", value: model.workspaces.joined(separator: ", "))
                    }
                    if let error = model.discoveryError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }
}

private enum BrowserKind {
    case safari
    case chrome

    var sectionTitle: String {
        switch self {
        case .safari: "Safari Tabs"
        case .chrome: "Chrome Tabs"
        }
    }

    func browser(from payload: ResourcePayload) -> BrowserWindow? {
        switch (self, payload) {
        case let (.safari, .browserWindow(browser)), let (.chrome, .chromeWindow(browser)):
            browser
        default:
            nil
        }
    }

    func payload(_ browser: BrowserWindow) -> ResourcePayload {
        switch self {
        case .safari: .browserWindow(browser)
        case .chrome: .chromeWindow(browser)
        }
    }
}

private struct LaunchReportView: View {
    let report: LaunchReport
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Couldn’t Fully Open \(report.projectName)").font(.title2)
            if !report.validationIssues.isEmpty {
                ForEach(Array(report.validationIssues.enumerated()), id: \.offset) { _, issue in
                    Label("\(issue.field): \(issue.message)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            List(report.results) { result in
                HStack(alignment: .top) {
                    Image(systemName: resultIcon(result.outcome))
                        .foregroundStyle(resultColor(result.outcome))
                    VStack(alignment: .leading) {
                        Text(result.resourceName)
                        if let detail = resultDetail(result.outcome) {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minHeight: 180)
            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .accessibilityIdentifier("dismiss-launch-report-button")
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 300)
    }

    private func resultIcon(_ outcome: ResourceLaunchOutcome) -> String {
        switch outcome {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "forward.circle.fill"
        }
    }

    private func resultColor(_ outcome: ResourceLaunchOutcome) -> Color {
        switch outcome {
        case .succeeded: .green
        case .failed: .red
        case .skipped: .orange
        }
    }

    private func resultDetail(_ outcome: ResourceLaunchOutcome) -> String? {
        switch outcome {
        case .succeeded: nil
        case let .failed(message), let .skipped(message): message
        }
    }
}

private struct WindowDelegateInstaller: NSViewRepresentable {
    let delegate: any NSWindowDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.delegate = delegate }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.delegate = delegate }
    }
}
