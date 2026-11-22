import UIKit
import FirebaseAuth

/// Loads and caches profile photos from the Lingora backend (GET /avatar/<uid>?v=<version>).
@MainActor
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()
    @Published private var images: [String: UIImage] = [:]
    private var inFlight: Set<String> = []

    private func key(_ uid: String, _ v: Int) -> String { "\(uid)-\(v)" }

    func image(uid: String, version: Int) -> UIImage? { images[key(uid, version)] }

    /// Shows a just-picked photo right away, before the server round trip.
    func set(_ image: UIImage, uid: String, version: Int) { images[key(uid, version)] = image }

    func load(uid: String, version: Int) async {
        let k = key(uid, version)
        guard images[k] == nil, !inFlight.contains(k), let base = Backend.apiBaseURL,
              let user = Auth.auth().currentUser else { return }
        inFlight.insert(k)
        defer { inFlight.remove(k) }
        var comps = URLComponents(url: base.appendingPathComponent("avatar").appendingPathComponent(uid), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "v", value: String(version))]
        guard let url = comps?.url, let token = try? await user.getIDToken() else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .returnCacheDataElseLoad
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else { return }
        images[k] = img
    }

    /// Square-crops and shrinks a photo to a small JPEG for upload.
    nonisolated static func prepare(_ image: UIImage, side: CGFloat = 320) -> Data? {
        let s = min(image.size.width, image.size.height)
        guard s > 0 else { return nil }
        let scale = side / s
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        for q in [0.8, 0.65, 0.5, 0.35] {
            if let d = out.jpegData(compressionQuality: q), d.count < 170_000 { return d }
        }
        return nil
    }
}
