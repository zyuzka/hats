import AppKit
import SwiftUI

extension HatListView {
    func strandedView(_ banner: DeadEndBanner) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(banner.line).font(.system(size: 11))
            if let hat = banner.signInTo {
                Button(hat.loginAction) { model.actions?.relogin(hat.id) }
                    .controlSize(.small)
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 10).padding(.bottom, 6)
    }

    var fullDiskAccessView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(HatsCopy.fullDiskAccessBanner).font(.system(size: 11))
            Button(HatsCopy.fullDiskAccessButton) {
                if let url = BrowserChoice.fullDiskAccessSettings { NSWorkspace.shared.open(url) }
            }
            .controlSize(.small)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 10).padding(.bottom, 6)
    }

    func bannerView(_ record: AutoSwitchRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(HatsCopy.banner(record, fromTitle: snapshot.bannerFromTitle)).font(.system(size: 11))
            Button("Switch back now") { model.actions?.switchBack() }.controlSize(.small)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 10).padding(.bottom, 6)
    }
}
