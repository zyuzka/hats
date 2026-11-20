import AppKit
import SwiftUI

final class CodexSignInModel: ObservableObject {
    @Published var trouble: String?

    let title: String
    let text: String
    var stop: () -> Void = { Journal.log("codex.signIn.stopIgnored") }

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

struct CodexSignInView: View {
    @ObservedObject var model: CodexSignInModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(model.text).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let trouble = model.trouble {
                Text(trouble).font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.stop() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

final class CodexSignInFlow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var closing = false
    private(set) var run: CodexSignInRun?

    var isRunning: Bool { run?.isInFlight ?? false }

    func begin(
        _ model: CodexSignInModel,
        hat: String,
        browser: BrowserChoice,
        then: @escaping (CodexSignInRun.Ending) -> Void
    ) throws {
        guard let wrapper = try browser.wrapperScript() else { throw CodexError.noBrowser(hat) }
        let run = CodexSignInRun(world: CodexSignInWorld(
            open: { url in try CodexSignInFlow.open(url, with: wrapper) },
            send: { request in
                OneShotRequest.answer(to: request, within: CodexOAuth.budget, unreachable: (0, nil)) { ($0, $1) }
            }
        ))
        model.stop = { [weak run] in run?.cancel() }
        run.ended = { [weak self, weak run] ending in
            if let run { self?.settle(run) }
            then(ending)
        }
        self.run = run
        show(model)
        do {
            try run.start()
        } catch {
            settle(run)
            throw error
        }
    }

    func track(_ run: CodexSignInRun) { self.run = run }

    func settle(_ ended: CodexSignInRun) {
        guard run === ended else { return }
        close()
        run = nil
    }

    func showTheWindow() { window?.makeKeyAndOrderFront(nil) }

    static func open(_ url: URL, with wrapper: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [wrapper.path, url.absoluteString]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private func show(_ model: CodexSignInModel) {
        DockPresence.aWindowIsAboutToOpen()
        let window = NSWindow(contentViewController: NSHostingController(rootView: CodexSignInView(model: model)))
        window.title = "Sign in to Codex"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        guard let window else { return }
        closing = true
        window.close()
        self.window = nil
        closing = false
    }

    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }
        window = nil
        run?.cancel()
    }
}
