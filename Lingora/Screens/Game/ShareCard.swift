import SwiftUI
import UniformTypeIdentifiers

/// A square card to share on Instagram, WhatsApp, etc.: big number, what it means, Lingora branding.
struct ShareCard: View {
    let icon: String
    let value: String
    let title: String
    let subtitle: String
    var color: Color = .orange

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: icon).font(.system(size: 120, weight: .bold)).foregroundStyle(.white)
                .frame(width: 260, height: 260).background(color, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            Text(verbatim: value).font(.system(size: 120, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text(verbatim: title).font(.system(size: 54, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(verbatim: subtitle).font(.system(size: 34, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 36))
                Text(verbatim: "Lingora").font(.system(size: 40, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.bottom, 40)
        }
        .padding(60)
        .frame(width: 1080, height: 1350)
        .background(LinearGradient(colors: [Color(hex: 0x5E8C6A), Color(hex: 0x2F5240)], startPoint: .top, endPoint: .bottom))
    }

    /// The card as PNG data (1080×1350, Instagram portrait).
    @MainActor
    func png() -> Data {
        let r = ImageRenderer(content: self)
        r.scale = 1
        return r.uiImage?.pngData() ?? Data()
    }
}

/// Rendered only when the share sheet asks for it, not on every screen update.
struct ShareCardFile: Transferable {
    let card: ShareCard
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in await MainActor.run { item.card.png() } }
    }
}

/// A share button for a card.
struct ShareCardButton: View {
    @Environment(\.theme) private var theme
    let card: ShareCard
    var label: String = L("Share")

    var body: some View {
        ShareLink(item: ShareCardFile(card: card), preview: SharePreview(card.title, image: Image(systemName: card.icon))) {
            Label(label, systemImage: "square.and.arrow.up").font(.fig(15, .semibold))
                .foregroundStyle(theme.ad)
                .padding(.horizontal, 16).frame(height: 40)
                .background(theme.at, in: Capsule())
        }
    }
}
