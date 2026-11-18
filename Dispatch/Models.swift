import Foundation
import Security

struct Account: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var email = ""
    var user = ""
    var imapHost = ""
    var imapPort = 993
    var smtpHost = ""
    var smtpPort = 465
    var spam: String?
    var trash: String?
    var sent: String?
    var folders: [String]?

    var title: String {
        name.isEmpty ? email : name
    }

    var login: String {
        user.isEmpty ? email : user
    }

    var otherFolders: [String] {
        (folders ?? []).filter { $0.uppercased() != "INBOX" && $0 != spam && $0 != trash }
    }

    var syncedFolders: [String] {
        ["INBOX"] + otherFolders + [spam, trash].compactMap { $0 }
    }

    func title(_ filter: Filter) -> String {
        switch filter {
        case .unread: "Ungelesen"
        case .read: "Gelesen"
        case .all: "Alle"
        case .favorites: "Favoriten"
        case .verified: "Verifiziert"
        case .shared: "Alle E-Mails"
        case .folder(let name):
            name == spam ? "Spam" : name == trash ? "Papierkorb" : name == sent ? "Gesendet" : folderName(name)
        }
    }

    func icon(_ filter: Filter) -> String {
        switch filter {
        case .unread: return "envelope.badge"
        case .read: return "envelope.open"
        case .all: return "tray.full"
        case .favorites: return "star"
        case .verified: return "checkmark.seal"
        case .shared: return "tray.2"
        case .folder(let name):
            let lower = folderName(name).lowercased()
            if name == spam { return "xmark.bin" }
            if name == trash { return "trash" }
            if name == sent { return "paperplane" }
            if lower.contains("entw") || lower.contains("draft") { return "doc" }
            if lower.contains("archiv") { return "archivebox" }
            return "folder"
        }
    }
}

struct Mail: Codable, Identifiable, Hashable {
    let uid: Int
    let folder: String
    var from: String
    var to: String
    var cc: String
    var subject: String
    var date: Date
    var seen: Bool
    var flagged: Bool
    var messageID: String
    var account: UUID?

    var id: String {
        (account?.uuidString ?? "") + "/" + folder + "/" + String(uid)
    }

    var inbox: Bool {
        folder.uppercased() == "INBOX"
    }
}

enum Filter: Hashable {
    case unread, read, all, favorites, verified, shared
    case folder(String)
}

enum Destination {
    case inbox, spam, trash
}

func matches(_ rule: String, _ from: String) -> Bool {
    let sender = address(from).lowercased()
    var pattern = rule.trimmingCharacters(in: .whitespaces).lowercased()
    if pattern.hasPrefix("*") {
        pattern.removeFirst()
    }
    if pattern.isEmpty {
        return false
    }
    if pattern.hasPrefix("@") {
        return sender.hasSuffix(pattern)
    }
    if !pattern.contains("@") {
        return sender.hasSuffix("@" + pattern)
    }
    return sender == pattern
}

struct Attachment: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let data: Data
}

struct Draft: Identifiable {
    let id = UUID()
    var account: UUID?
    var to = ""
    var cc = ""
    var subject = ""
    var body = ""
    var attachments: [Attachment] = []
    var reply = ""
}

func folderName(_ name: String) -> String {
    let last = name.split(whereSeparator: { $0 == "/" || $0 == "." }).last.map(String.init) ?? name
    var result = ""
    var rest = Substring(last)
    while let amp = rest.firstIndex(of: "&") {
        result += rest[..<amp]
        let after = rest[rest.index(after: amp)...]
        guard let dash = after.firstIndex(of: "-") else {
            return result + after
        }
        let chunk = after[..<dash]
        if chunk.isEmpty {
            result += "&"
        } else {
            var encoded = chunk.replacingOccurrences(of: ",", with: "/")
            while encoded.count % 4 != 0 {
                encoded += "="
            }
            if let data = Data(base64Encoded: encoded), let text = String(data: data, encoding: .utf16BigEndian) {
                result += text
            }
        }
        rest = after[after.index(after: dash)...]
    }
    return result + rest
}

func savePassword(_ password: String, for id: UUID) {
    deletePassword(for: id)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dispatch",
        kSecAttrAccount as String: id.uuidString,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        kSecValueData as String: Data(password.utf8),
    ]
    SecItemAdd(query as CFDictionary, nil)
}

func loadPassword(for id: UUID) -> String {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dispatch",
        kSecAttrAccount as String: id.uuidString,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    SecItemCopyMatching(query as CFDictionary, &result)
    return (result as? Data).map { String(decoding: $0, as: UTF8.self) } ?? ""
}

func deletePassword(for id: UUID) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dispatch",
        kSecAttrAccount as String: id.uuidString,
    ]
    SecItemDelete(query as CFDictionary)
}
