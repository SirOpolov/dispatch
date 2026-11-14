import Foundation
import Observation

@MainActor
@Observable
class Store {
    var accounts: [Account] = []
    var mails: [Mail] = []
    var syncing = false
    var error: String?
    var log: [String] = []
    var lastSync: Date?
    var currentID: UUID? {
        didSet {
            UserDefaults.standard.set(currentID?.uuidString, forKey: "current")
            mails = loadMails(current?.id)
            error = nil
        }
    }

    private let accountsFile = URL.documentsDirectory.appending(path: "accounts.json")

    init() {
        if let data = try? Data(contentsOf: accountsFile), let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        }
        currentID = UserDefaults.standard.string(forKey: "current").flatMap(UUID.init)
        mails = loadMails(current?.id)
    }

    var current: Account? {
        accounts.first { $0.id == currentID } ?? accounts.first
    }

    func count(_ filter: Filter) -> Int {
        mails.filter(filter.matches).count
    }

    func connect(_ account: Account, password: String) async throws -> Account {
        var checked = account
        let imap = try await IMAP(account: account, password: password)
        defer { imap.close() }
        let folders = try await imap.folders()
        checked.spam = folders.spam
        checked.trash = folders.trash
        let smtp = try await SMTP(account: account, password: password)
        smtp.close()
        return checked
    }

    func add(_ account: Account, password: String) {
        savePassword(password, for: account.id)
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        saveAccounts()
        currentID = account.id
        note("Konto gespeichert: " + account.email)
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        deletePassword(for: account.id)
        try? FileManager.default.removeItem(at: directory(account.id))
        saveAccounts()
        currentID = accounts.first?.id
        note("Konto entfernt: " + account.email)
    }

    func sync() async {
        guard var account = current, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let imap = try await IMAP(account: account, password: loadPassword(for: account.id))
            defer { imap.close() }
            if account.spam == nil || account.trash == nil {
                let folders = try await imap.folders()
                account.spam = folders.spam
                account.trash = folders.trash
                updateAccount(account)
            }
            var all = loadMails(account.id)
            var fresh = 0
            for box in Box.allCases {
                guard let folder = account.folder(box) else { continue }
                try await imap.select(folder)
                let uids = try await imap.search()
                let present = Set(uids)
                all.removeAll { $0.box == box && !present.contains($0.uid) }
                if !uids.isEmpty {
                    let flags = try await imap.flags()
                    for index in all.indices where all[index].box == box {
                        all[index].seen = flags[all[index].uid] ?? all[index].seen
                    }
                }
                let known = Set(all.filter { $0.box == box }.map(\.uid))
                let missing = Array(uids.filter { !known.contains($0) }.suffix(500))
                let loaded = try await imap.headers(missing, box: box)
                fresh += loaded.count
                all += loaded
            }
            saveMails(all, account.id)
            if current?.id == account.id {
                mails = all
                error = nil
            }
            lastSync = .now
            note(account.email + ": " + String(fresh) + " neu")
        } catch {
            fail(error)
        }
    }

    func raw(_ mail: Mail) async -> Data? {
        guard let account = current, let folder = account.folder(mail.box) else { return nil }
        let file = directory(account.id).appending(path: mail.id + ".eml")
        if let data = try? Data(contentsOf: file) {
            if !mail.seen {
                await setSeen(mail, true)
            }
            return data
        }
        do {
            let data = try await withIMAP(account) { imap in
                try await imap.select(folder)
                let data = try await imap.body(mail.uid)
                if !mail.seen {
                    try await imap.setSeen(mail.uid, true)
                }
                return data
            }
            try? data.write(to: file)
            update(mail) { $0.seen = true }
            return data
        } catch {
            fail(error)
            return nil
        }
    }

    func setSeen(_ mail: Mail, _ seen: Bool) async {
        guard let account = current, let folder = account.folder(mail.box) else { return }
        update(mail) { $0.seen = seen }
        do {
            try await withIMAP(account) { imap in
                try await imap.select(folder)
                try await imap.setSeen(mail.uid, seen)
            }
        } catch {
            fail(error)
        }
    }

    func move(_ mail: Mail, to box: Box) async {
        guard let account = current, let folder = account.folder(mail.box) else { return }
        mails.removeAll { $0.id == mail.id }
        saveMails(mails, account.id)
        try? FileManager.default.removeItem(at: directory(account.id).appending(path: mail.id + ".eml"))
        do {
            try await withIMAP(account) { imap in
                try await imap.select(folder)
                if let target = account.folder(box), box != mail.box {
                    try await imap.move(mail.uid, to: target)
                } else {
                    try await imap.expunge(mail.uid)
                }
            }
        } catch {
            fail(error)
        }
        await sync()
    }

    func send(to: String, subject: String, body: String) async throws {
        guard let account = current else { return }
        let recipients = to.split { $0 == "," || $0 == ";" }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !recipients.isEmpty else {
            throw MailError("Kein Empfänger angegeben")
        }
        let smtp = try await SMTP(account: account, password: loadPassword(for: account.id))
        defer { smtp.close() }
        try await smtp.deliver(from: account.email, to: recipients, message: message(account: account, to: recipients, subject: subject, body: body))
        note("Gesendet an " + recipients.joined(separator: ", "))
    }

    func clearCache() {
        guard let account = current else { return }
        try? FileManager.default.removeItem(at: directory(account.id))
        mails = []
        note("Cache geleert: " + account.email)
    }

    private func withIMAP<T>(_ account: Account, _ work: (IMAP) async throws -> T) async throws -> T {
        let imap = try await IMAP(account: account, password: loadPassword(for: account.id))
        defer { imap.close() }
        return try await work(imap)
    }

    private func update(_ mail: Mail, _ change: (inout Mail) -> Void) {
        guard let account = current, let index = mails.firstIndex(where: { $0.id == mail.id }) else { return }
        change(&mails[index])
        saveMails(mails, account.id)
    }

    private func updateAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        saveAccounts()
    }

    private func fail(_ error: Error) {
        self.error = error.localizedDescription
        note("Fehler: " + error.localizedDescription)
    }

    private func note(_ text: String) {
        log.append(Date.now.formatted(date: .omitted, time: .standard) + "  " + text)
        if log.count > 200 {
            log.removeFirst()
        }
    }

    private func directory(_ id: UUID) -> URL {
        let url = URL.documentsDirectory.appending(path: id.uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func loadMails(_ id: UUID?) -> [Mail] {
        guard let id, let data = try? Data(contentsOf: directory(id).appending(path: "mails.json")) else { return [] }
        return (try? JSONDecoder().decode([Mail].self, from: data)) ?? []
    }

    private func saveMails(_ mails: [Mail], _ id: UUID) {
        try? JSONEncoder().encode(mails).write(to: directory(id).appending(path: "mails.json"))
    }

    private func saveAccounts() {
        try? JSONEncoder().encode(accounts).write(to: accountsFile)
    }
}
