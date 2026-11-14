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

    var title: String {
        name.isEmpty ? email : name
    }

    var login: String {
        user.isEmpty ? email : user
    }

    func folder(_ box: Box) -> String? {
        switch box {
        case .inbox: "INBOX"
        case .spam: spam
        case .trash: trash
        }
    }
}

enum Box: String, Codable, CaseIterable {
    case inbox, spam, trash
}

struct Mail: Codable, Identifiable, Hashable {
    let uid: Int
    let box: Box
    var from: String
    var to: String
    var subject: String
    var date: Date
    var seen: Bool

    var id: String {
        box.rawValue + "-" + String(uid)
    }
}

enum Filter: Hashable {
    case unread, read, all, spam, trash

    var title: String {
        switch self {
        case .unread: "Ungelesen"
        case .read: "Gelesen"
        case .all: "Alle"
        case .spam: "Spam"
        case .trash: "Papierkorb"
        }
    }

    var icon: String {
        switch self {
        case .unread: "envelope.badge"
        case .read: "envelope.open"
        case .all: "tray.full"
        case .spam: "xmark.bin"
        case .trash: "trash"
        }
    }

    func matches(_ mail: Mail) -> Bool {
        switch self {
        case .unread: mail.box == .inbox && !mail.seen
        case .read: mail.box == .inbox && mail.seen
        case .all: mail.box == .inbox
        case .spam: mail.box == .spam
        case .trash: mail.box == .trash
        }
    }
}

func savePassword(_ password: String, for id: UUID) {
    deletePassword(for: id)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "laufbursche",
        kSecAttrAccount as String: id.uuidString,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        kSecValueData as String: Data(password.utf8),
    ]
    SecItemAdd(query as CFDictionary, nil)
}

func loadPassword(for id: UUID) -> String {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "laufbursche",
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
        kSecAttrService as String: "laufbursche",
        kSecAttrAccount as String: id.uuidString,
    ]
    SecItemDelete(query as CFDictionary)
}
