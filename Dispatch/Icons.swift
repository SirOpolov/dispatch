import Observation
import SwiftUI
import UIKit

let freemail: Set<String> = [
    "web.de", "gmx.de", "gmx.net", "gmx.at", "gmx.ch", "gmail.com", "googlemail.com", "outlook.com", "outlook.de",
    "hotmail.com", "hotmail.de", "live.com", "live.de", "yahoo.com", "yahoo.de", "icloud.com", "me.com", "mac.com",
    "t-online.de", "freenet.de", "aol.com", "aol.de", "posteo.de", "mailbox.org", "proton.me", "protonmail.com", "online.de",
]

func senderDomain(_ from: String) -> String {
    let host = address(from).lowercased().split(separator: "@").last.map(String.init) ?? ""
    let labels = host.split(separator: ".").map(String.init)
    guard labels.count > 2 else { return host }
    let keep = labels[labels.count - 1].count == 2 && ["co", "com", "org", "net", "ac", "gov"].contains(labels[labels.count - 2]) ? 3 : 2
    return labels.suffix(keep).joined(separator: ".")
}

func placeholderColor(_ text: String) -> Color {
    let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .teal, .green, .cyan, .mint, .brown]
    let sum = text.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[sum % palette.count]
}

@MainActor
@Observable
class Icons {
    var images: [String: UIImage] = [:]
    var custom: [String: UIImage] = [:]
    private var pending: Set<String> = []
    private let folder = URL.documentsDirectory.appending(path: "icons")
    private let customFolder = URL.documentsDirectory.appending(path: "custom-icons")

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: customFolder, withIntermediateDirectories: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: customFolder, includingPropertiesForKeys: nil)) ?? [] {
            if let rule = file.deletingPathExtension().lastPathComponent.removingPercentEncoding, let image = UIImage(contentsOfFile: file.path) {
                custom[rule] = image
            }
        }
    }

    func image(for from: String, trusted: [String]) -> UIImage? {
        if let rule = trusted.first(where: { custom[$0] != nil && matches($0, from) }) {
            return custom[rule]
        }
        return images[senderDomain(from)]
    }

    func load(_ from: String) async {
        let domain = senderDomain(from)
        let enabled = UserDefaults.standard.object(forKey: "icons") as? Bool ?? true
        guard enabled, !domain.isEmpty, images[domain] == nil, !pending.contains(domain), !freemail.contains(domain) else { return }
        pending.insert(domain)
        let file = folder.appending(path: domain + ".png")
        let miss = folder.appending(path: domain + ".none")
        if let image = UIImage(contentsOfFile: file.path) {
            images[domain] = image
            return
        }
        if let date = (try? FileManager.default.attributesOfItem(atPath: miss.path))?[.modificationDate] as? Date, date > .now.addingTimeInterval(-7 * 86400) {
            return
        }
        for host in [domain, "www." + domain] {
            for path in ["/apple-touch-icon.png", "/favicon.ico"] {
                guard let url = URL(string: "https://" + host + path) else { continue }
                let request = URLRequest(url: url, timeoutInterval: 8)
                guard let result = try? await URLSession.shared.data(for: request),
                      (result.1 as? HTTPURLResponse)?.statusCode == 200,
                      let image = UIImage(data: result.0),
                      image.size.width >= 16 else { continue }
                try? image.pngData()?.write(to: file)
                images[domain] = image
                return
            }
        }
        try? Data().write(to: miss)
    }

    func setCustom(_ image: UIImage?, for rule: String) {
        let file = customFolder.appending(path: (rule.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? rule) + ".png")
        guard let image else {
            custom[rule] = nil
            try? FileManager.default.removeItem(at: file)
            return
        }
        let side: CGFloat = 256
        let scale = max(side / image.size.width, side / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let scaled = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        try? scaled.pngData()?.write(to: file)
        custom[rule] = scaled
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        images = [:]
        pending = []
    }
}

struct Avatar: View {
    @Environment(Store.self) private var store
    @Environment(Icons.self) private var icons
    let from: String
    var size: CGFloat = 38

    var body: some View {
        Group {
            if let image = icons.image(for: from, trusted: store.trusted) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .background(Color.white)
            } else {
                Placeholder(text: address(from), size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: senderDomain(from)) {
            await icons.load(from)
        }
    }
}

struct Placeholder: View {
    let text: String
    var size: CGFloat = 38

    var body: some View {
        let clean = text.trimmingCharacters(in: CharacterSet(charactersIn: "*@ ")).lowercased()
        Text(clean.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(placeholderColor(clean), in: Circle())
    }
}

struct RuleIcon: View {
    @Environment(Icons.self) private var icons
    let rule: String
    var size: CGFloat = 38

    var body: some View {
        Group {
            if let image = icons.custom[rule] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Placeholder(text: rule, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
