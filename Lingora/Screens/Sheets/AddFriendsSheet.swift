import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

struct AddFriendsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var copied = false
    @State private var contactsFound = false

    private var handle: String { model.s.user?.handle ?? "@you" }
    private var inviteURL: String { "https://lingora.app/add/\(handle.dropFirst())" }

    private var results: [SampleFriends.Suggested] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
        guard !q.isEmpty else { return SampleFriends.suggested }
        return SampleFriends.suggested.filter { $0.name.lowercased().contains(q) || $0.handle.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Add friends")).font(.fig(24, .bold))
                    Spacer()
                    BackButton(systemName: "xmark") { dismiss() }
                }
                .padding(.top, 20)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                    TextField(L("Search by username"), text: $query)
                        .font(.fig(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 16).frame(height: 52)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.line, lineWidth: 1.5))

                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, p in
                        let added = model.s.addedFriends.contains(p.id)
                        HStack(spacing: 12) {
                            Avatar(initial: String(p.name.prefix(1)), hue: Hue(h: p.hue), size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.fig(15, .semibold))
                                Text(verbatim: "\(p.handle) · \(p.sub)").font(.fig(13)).foregroundStyle(theme.muted)
                            }
                            Spacer()
                            PillButton(title: added ? L("Requested") : L("Add"), bg: added ? theme.at : theme.a,
                                       fg: added ? theme.ad : .white, height: 34) {
                                if !added { model.toggle(\.addedFriends, p.id) }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(theme.line).frame(height: 1) } }
                    }
                    if results.isEmpty {
                        Text(L("No one found. Share your link instead.")).font(.fig(14)).foregroundStyle(theme.muted).padding(16)
                    }
                }
                .card(padding: 0)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = inviteURL
                        copied = true
                        Haptics.success()
                    } label: {
                        Label(copied ? L("Link copied") : L("Share invite link"), systemImage: copied ? "checkmark" : "link")
                    }
                    .buttonStyle(.secondary)
                    Button {
                        contactsFound = true
                        Haptics.tap()
                    } label: {
                        Label(contactsFound ? L("2 friends found") : L("From contacts"), systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.secondary)
                }

                VStack(spacing: 12) {
                    if let qr = QRCode.image(for: inviteURL) {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                            .frame(width: 170, height: 170)
                            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text(L("Scan to add %@", handle)).font(.fig(15, .semibold))
                    ShareLink(item: URL(string: inviteURL)!) {
                        Label(L("Share"), systemImage: "square.and.arrow.up").font(.fig(14, .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .card()
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(theme.ground)
    }
}

enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
