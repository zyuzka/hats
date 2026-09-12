import AppKit
import SwiftUI

struct LiveSessionRow: Identifiable, Equatable {
    let id: Int32
    let wearing: String
    let running: String
    let moves: String

    static func rows(
        sessions: [Session],
        wearingTitle: String?,
        gateway facts: GatewayFacts,
        horizon: String
    ) -> [LiveSessionRow] {
        let gateway = facts.addresses.current
        let retired = facts.addresses.retired
        let ours = facts.addresses.all
        return sessions.map { session in
            let follows = facts.isServing && session.route.isThrough(anyOf: ours)
            return LiveSessionRow(
                id: session.pid,
                wearing: follows ? wearingTitle ?? "—" : "—",
                running: session.elapsed,
                moves: moves(
                    of: session.route,
                    gatewayAt: gateway,
                    retiredAt: retired,
                    serving: facts.isServing,
                    settleSeconds: facts.settleSeconds,
                    horizon: horizon
                )
            )
        }
    }

    static func moves(
        of route: SessionRoute,
        gatewayAt gateway: String,
        retiredAt retired: String? = nil,
        serving: Bool,
        settleSeconds: Int,
        horizon: String
    ) -> String {
        switch route {
        case .unknown:
            return "unknown — its environment could not be read"
        case .direct:
            return "direct — \(horizon)"
        case .pointedAt where route.isThrough(gatewayAt: gateway):
            return serving
                ? "through the gateway — " + HatsCopy.followsASwitch(settleSeconds: settleSeconds)
                : "through the gateway, which is off — stuck until it serves again"
        case .pointedAt where retired.map({ route.isThrough(gatewayAt: $0) }) ?? false:
            return "through the gateway on the port it started with, still served — that listener "
                + "closes once no session needs it"
        case .pointedAt(let url):
            return "points at \(shown(url)) — not this gateway"
        }
    }

    static func shown(_ value: String, limit: Int = 60) -> String {
        let oneLine = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return oneLine.count > limit ? String(oneLine.prefix(limit)) + "…" : oneLine
    }
}

struct LiveSessionsView: View {
    @ObservedObject var model: HatsModel

    private var snapshot: HatsSnapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(HatsCopy.sessions(
                    snapshot.sessions,
                    wearing: snapshot.wearing?.title,
                    gatewayBaseURLs: addresses.all,
                    serving: snapshot.gateway.isServing
                ))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(HatsCopy.gateway(snapshot.gateway)).font(.system(size: 11))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(pillColour))
            }
            switch snapshot.sessions {
            case .unknown:
                Text("the process table could not be read").font(.system(size: 12)).foregroundStyle(.secondary)
            case .counted(let live):
                Table(rows(live)) {
                    TableColumn("pid") { Text(String($0.id)) }.width(60)
                    TableColumn("wearing") { Text($0.wearing) }
                    TableColumn("running") { Text($0.running) }.width(80)
                    TableColumn("moves") { Text($0.moves) }
                }
                .frame(height: TableHeight.forRows(rows(live).count, upTo: 12))
            }
            Text("A direct session — started in a shell opened before the app was up — keeps the hat it started "
                + "on until its next token renewal, and which hat that is, nobody here knows.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider().padding(.vertical, 2)
            relaySeen
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 220)
    }

    private var relaySeen: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(HatsCopy.relaySessions(snapshot.gatewaySessions, serving: snapshot.gateway.isServing))
                .font(.system(size: 13, weight: .semibold))
            if !snapshot.gatewaySessions.isEmpty {
                Table(snapshot.gatewaySessions) {
                    TableColumn("session") { Text(HatsCopy.shortSession($0.session)) }.width(90)
                    TableColumn("requests") { Text(String($0.requests)) }.width(70)
                    TableColumn("last") { Text(String($0.lastStatus)) }.width(50)
                    TableColumn("credential") { Text($0.credential) }
                }
                .frame(height: TableHeight.forRows(snapshot.gatewaySessions.count, upTo: 8))
            }
            Text(HatsCopy.theTwoSessionListsDiffer)
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var addresses: GatewayAddresses { snapshot.gatewayAddresses }

    private var pillColour: Color {
        snapshot.gateway.isServing ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.2)
    }

    private func rows(_ live: [Session]) -> [LiveSessionRow] {
        LiveSessionRow.rows(
            sessions: live,
            wearingTitle: snapshot.wearing?.title,
            gateway: GatewayFacts.of(snapshot: snapshot),
            horizon: snapshot.horizon
        )
    }
}

final class LiveSessionsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show(model: HatsModel) {
        if let window {
            fitToItsContent(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: LiveSessionsView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "Live sessions"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        fitToItsContent(window)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func fitToItsContent(_ window: NSWindow) {
        guard let view = window.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        window.setContentSize(view.fittingSize)
    }

    func windowDidResignKey(_ notification: Notification) {
        (notification.object as? NSWindow)?.close()
    }
}
