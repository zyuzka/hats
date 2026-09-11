import AppKit
import SwiftUI

struct HatsRootView: View {
    @ObservedObject var model: HatsModel

    var body: some View {
        HatListView(model: model)
    }
}

final class HatsPopover: NSObject, NSPopoverDelegate {
    let model = HatsModel()
    private let popover = NSPopover()
    private let host: NSHostingController<HatsRootView>
    var willShow: (() -> Void)?
    var didClose: (() -> Void)?
    private(set) var isClosing = false

    override init() {
        host = NSHostingController(rootView: HatsRootView(model: model))
        host.sizingOptions = .preferredContentSize
        super.init()
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            isClosing = true
            popover.performClose(nil)
            return
        }
        show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard !popover.isShown else { return }
        isClosing = false
        host.view.layoutSubtreeIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.willShow?()
        }
    }

    func close() {
        isClosing = true
        popover.performClose(nil)
    }

    func popoverWillClose(_ notification: Notification) { isClosing = true }

    func popoverDidClose(_ notification: Notification) {
        isClosing = false
        didClose?()
    }
}
