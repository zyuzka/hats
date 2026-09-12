import AppKit
import SwiftUI

struct ReleasesView: View {
    let notes: [ReleaseNote]
    let running: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if notes.isEmpty { empty } else { ForEach(notes) { note in entry(note) } }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 440)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No release notes in this build").font(.system(size: 13, weight: .semibold))
            Text(HatsCopy.releaseNotesMissing(running: running))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func paragraph(_ line: String) -> some View {
        if let body = ReleaseNotes.bullet(line) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\u{2022}").foregroundStyle(.secondary)
                styled(body).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            styled(line).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func styled(_ text: String) -> Text {
        guard let attributed = try? AttributedString(markdown: text) else { return Text(text) }
        return Text(attributed)
    }

    private func entry(_ note: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note.version).font(.system(size: 15, weight: .semibold))
                if note.version == running {
                    Text("running now")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                }
                Spacer()
                Text(note.dateline).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(Array(note.lines.enumerated()), id: \.offset) { _, line in
                paragraph(line)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

final class ReleasesWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(running: String, notes: [ReleaseNote]? = nil) {
        DockPresence.aWindowIsAboutToOpen()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let notes = notes ?? ReleaseNotes.fromTheBundle()
        let controller = NSHostingController(rootView: ReleasesView(notes: notes, running: running))
        let window = NSWindow(contentViewController: controller)
        window.title = "Hats releases"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        (notification.object as? NSWindow)?.close()
    }
}
