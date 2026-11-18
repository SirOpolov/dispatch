import BackgroundTasks
import Foundation
import Observation
import UserNotifications

let refreshTask = "de.siropolov.dispatch.refresh"

func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshTask)
    request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
    try? BGTaskScheduler.shared.submit(request)
}

func mailCount(_ count: Int) -> String {
    count == 1 ? "1 E-Mail" : String(count) + " E-Mails"
}

@MainActor
@Observable
class Store {
    var accounts: [Account] = []
    var mails: [Mail] = []
    var syncing = false
    var error: String?
    var log: [String] = []
    var lastSync: Date?
    var toast: String?
    var done = 0
    var failed = 0
    var trusted: [String] = UserDefaults.standard.stringArray(forKey: "trusted") ?? [] {
        didSet {
            UserDefaults.standard.set(trusted, forKey: "trusted")
        }
    }
    var blocked: [String] = UserDefaults.standard.stringArray(forKey: "blocked") ?? [] {
        didSet {
            UserDefaults.standard.set(blocked, forKey: "blocked")
        }
    }
    var unified = UserDefaults.standard.bool(forKey: "unified") {
        didSet {
            UserDefaults.standard.set(unified, forKey: "unified")
            reload()
        }
    }
    var currentID: UUID? {
        didSet {
            UserDefaults.standard.set(currentID?.uuidString, forKey: "current")
            reload()
        }
    }

    private let accountsFile = URL.documentsDirectory.appending(path: "accounts.json")

    init() {
        if let data = try? Data(contentsOf: accountsFile), let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        }
        currentID = UserDefaults.standard.string(forKey: "current").flatMap(UUID.init)
        reload()
    }

    var current: Account? {
        accounts.first { $0.id == currentID } ?? accounts.first
    }

    var scope: String {
        unified ? "unified" : current?.id.uuidString ?? ""
    }

    func account(of mail: Mail) -> Account? {
        accounts.first { $0.id == mail.account }
    }

    func isTrusted(_ mail: Mail) -> Bool {
        trusted.contains { matches($0, mail.from) }
    }

    func isBlocked(_ mail: Mail) -> Bool {
        blocked.contains { matches($0, mail.from) }
    }

    func list(_ filter: Filter) -> [Mail] {
        mails.filter { mail in
            let owner = account(of: mail)
            let junk = mail.folder == owner?.spam || mail.folder == owner?.trash
            switch filter {
            case .unread: return mail.inbox && !mail.seen && !isBlocked(mail)
            case .read: return mail.inbox && mail.seen && !isBlocked(mail)
            case .all: return mail.inbox && !isBlocked(mail)
            case .favorites: return mail.flagged && mail.folder != owner?.trash
            case .verified: return mail.inbox && isTrusted(mail)
            case .shared: return !junk && !isBlocked(mail)
            case .folder(let name): return mail.folder == name
            }
        }
    }

    func unread(_ filter: Filter) -> Int {
        list(filter).filter { !$0.seen }.count
    }

    func confirm(_ text: String) {
        toast = text
        done += 1
    }

    func select(_ account: Account?) {
        if let account {
            currentID = account.id
            unified = false
            confirm("Gewechselt zu " + account.title)
        } else {
            unified = true
            confirm("Alle Konten")
        }
    }

    func connect(_ account: Account, password: String) async throws -> Account {
        var checked = account
        do {
            let imap = try await IMAP(account: account, password: password)
            defer { imap.close() }
            let folders = try await imap.folders()
            checked.spam = folders.spam
            checked.trash = folders.trash
            checked.sent = folders.sent
            checked.folders = folders.all
        } catch {
            throw MailError("IMAP: " + error.localizedDescription)
        }
        do {
            let smtp = try await SMTP(account: account, password: password)
            smtp.close()
        } catch {
            throw MailError("SMTP: " + error.localizedDescription)
        }
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
        unified = false
        currentID = account.id
        note("Konto gespeichert: " + account.email)
        confirm("Verbunden mit " + account.email)
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        deletePassword(for: account.id)
        try? FileManager.default.removeItem(at: directory(account.id))
        saveAccounts()
        if accounts.count < 2 {
            unified = false
        }
        currentID = accounts.first?.id
        note("Konto entfernt: " + account.email)
        confirm("Konto entfernt")
    }

    func trust(_ rule: String) {
        let clean = rule.trimmingCharacters(in: .whitespaces).lowercased()
        guard !clean.isEmpty, !trusted.contains(clean) else { return }
        trusted.append(clean)
        blocked.removeAll { $0 == clean }
        confirm(clean + " ist vertrauenswürdig")
    }

    func block(_ rule: String) async {
        let clean = rule.trimmingCharacters(in: .whitespaces).lowercased()
        guard !clean.isEmpty, !blocked.contains(clean) else { return }
        blocked.append(clean)
        trusted.removeAll { $0 == clean }
        let junk = mails.filter { $0.inbox && matches(clean, $0.from) }
        if junk.isEmpty {
            confirm(clean + " gilt als Spam")
        } else {
            await move(junk, to: .spam, mailCount(junk.count) + " von " + clean + " in Spam verschoben")
        }
    }

    @discardableResult
    func sync() async -> Int {
        guard !syncing, !accounts.isEmpty else { return 0 }
        syncing = true
        defer { syncing = false }
        var count = 0
        var problem: String?
        for account in unified ? accounts : [current].compactMap({ $0 }) {
            do {
                let fresh = try await download(account)
                count += fresh.count
                note(account.email + ": " + String(fresh.count) + " neu")
            } catch {
                problem = account.email + ": " + error.localizedDescription
                note("Fehler " + (problem ?? ""))
            }
        }
        error = problem
        lastSync = .now
        reload()
        return count
    }

    func refresh() async {
        let count = await sync()
        if error == nil {
            confirm(count == 0 ? "Keine neuen E-Mails" : mailCount(count) + " neu")
        } else {
            toast = error
            failed += 1
        }
    }

    func backgroundSync() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        for account in accounts {
            guard let fresh = try? await download(account) else { continue }
            announce(fresh.filter { $0.inbox && !$0.seen }, account)
        }
        reload()
    }

    func raw(_ mail: Mail) async -> Data? {
        guard let owner = account(of: mail) else { return nil }
        let file = cacheFile(mail)
        if let data = try? Data(contentsOf: file) {
            if !mail.seen {
                _ = await mark([mail], "\\Seen", true) { $0.seen = true }
            }
            return data
        }
        do {
            let data = try await withIMAP(owner) { imap in
                try await imap.select(mail.folder)
                let data = try await imap.body(mail.uid)
                if !mail.seen {
                    try await imap.store([mail.uid], "\\Seen", true)
                }
                return data
            }
            try? data.write(to: file)
            if let index = mails.firstIndex(where: { $0.id == mail.id }) {
                mails[index].seen = true
                persist(owner.id)
            }
            return data
        } catch {
            fail(error)
            return nil
        }
    }

    func setSeen(_ list: [Mail], _ seen: Bool) async {
        if await mark(list, "\\Seen", seen, { $0.seen = seen }) {
            confirm(seen ? "Als gelesen markiert" : "Als ungelesen markiert")
        }
    }

    func setFlagged(_ list: [Mail], _ flagged: Bool) async {
        if await mark(list, "\\Flagged", flagged, { $0.flagged = flagged }) {
            confirm(flagged ? "Zu Favoriten hinzugefügt" : "Aus Favoriten entfernt")
        }
    }

    func delete(_ list: [Mail]) async {
        await move(list, to: .trash, mailCount(list.count) + " gelöscht")
    }

    func move(_ list: [Mail], to destination: Destination, _ text: String) async {
        guard !list.isEmpty else { return }
        let ids = Set(list.map(\.id))
        mails.removeAll { ids.contains($0.id) }
        for mail in list {
            try? FileManager.default.removeItem(at: cacheFile(mail))
        }
        do {
            for (id, group) in Dictionary(grouping: list, by: { $0.account }) {
                guard let account = accounts.first(where: { $0.id == id }) else { continue }
                persist(account.id)
                let target: String? = switch destination {
                case .inbox: "INBOX"
                case .spam: account.spam
                case .trash: account.trash
                }
                try await withIMAP(account) { imap in
                    for (folder, mails) in Dictionary(grouping: group, by: \.folder) {
                        try await imap.select(folder)
                        if let target, target != folder {
                            try await imap.move(mails.map(\.uid), to: target)
                        } else if destination == .trash {
                            try await imap.expunge(mails.map(\.uid))
                        }
                    }
                }
            }
            confirm(text)
        } catch {
            fail(error)
        }
        await sync()
    }

    func send(_ draft: Draft) async throws {
        guard let account = accounts.first(where: { $0.id == draft.account }) ?? current else { return }
        let recipients = addresses(draft.to) + addresses(draft.cc)
        guard !recipients.isEmpty else {
            throw MailError("Kein gültiger Empfänger angegeben")
        }
        let data = message(account: account, draft: draft)
        let smtp = try await SMTP(account: account, password: loadPassword(for: account.id))
        defer { smtp.close() }
        try await smtp.deliver(from: account.email, to: recipients, message: data)
        note("Gesendet an " + recipients.joined(separator: ", "))
        if let sent = account.sent {
            do {
                try await withIMAP(account) { imap in
                    try await imap.append(data, to: sent)
                }
            } catch {
                note("Ablage in Gesendet fehlgeschlagen: " + error.localizedDescription)
            }
        }
        confirm("Gesendet von " + account.email)
    }

    func clearCache() {
        for account in unified ? accounts : [current].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: directory(account.id))
        }
        mails = []
        note("Cache geleert")
        confirm("Cache geleert")
    }

    func rediscover() {
        for var account in unified ? accounts : [current].compactMap({ $0 }) {
            account.folders = nil
            updateAccount(account)
        }
        confirm("Ordner werden neu gesucht")
        Task {
            await sync()
        }
    }

    private func reload() {
        if unified {
            mails = accounts.flatMap { loadMails($0.id) }
        } else {
            mails = current.map { loadMails($0.id) } ?? []
        }
    }

    private func download(_ original: Account) async throws -> [Mail] {
        var account = original
        let imap = try await IMAP(account: account, password: loadPassword(for: account.id))
        defer { imap.close() }
        if account.folders == nil {
            let folders = try await imap.folders()
            account.spam = folders.spam
            account.trash = folders.trash
            account.sent = folders.sent
            account.folders = folders.all
            updateAccount(account)
        }
        var all = loadMails(account.id)
        let first = all.isEmpty
        var fresh: [Mail] = []
        for folder in account.syncedFolders {
            try await imap.select(folder)
            let uids = try await imap.search()
            let present = Set(uids)
            all.removeAll { $0.folder == folder && !present.contains($0.uid) }
            if !uids.isEmpty {
                let flags = try await imap.flags()
                for index in all.indices where all[index].folder == folder {
                    if let flag = flags[all[index].uid] {
                        all[index].seen = flag.seen
                        all[index].flagged = flag.flagged
                    }
                }
            }
            let known = Set(all.filter { $0.folder == folder }.map(\.uid))
            var loaded = try await imap.headers(uids.filter { !known.contains($0) }, folder: folder)
            for index in loaded.indices {
                loaded[index].account = account.id
            }
            all += loaded
            fresh += loaded
            if folder == "INBOX", let spam = account.spam {
                let junk = all.filter { $0.inbox && isBlocked($0) }
                if !junk.isEmpty {
                    try await imap.move(junk.map(\.uid), to: spam)
                    let ids = Set(junk.map(\.id))
                    all.removeAll { ids.contains($0.id) }
                    fresh.removeAll { ids.contains($0.id) }
                    note(account.email + ": " + mailCount(junk.count) + " in Spam verschoben")
                }
            }
        }
        saveMails(all, account.id)
        return first ? [] : fresh
    }

    private func announce(_ list: [Mail], _ account: Account) {
        guard !list.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = list.count == 1 ? senderName(list[0].from) : mailCount(list.count) + " neu"
        content.subtitle = account.title
        content.body = list.count == 1 ? list[0].subject : list.prefix(5).map { senderName($0.from) }.joined(separator: ", ")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func mark(_ list: [Mail], _ flag: String, _ on: Bool, _ change: (inout Mail) -> Void) async -> Bool {
        guard !list.isEmpty else { return false }
        let ids = Set(list.map(\.id))
        for index in mails.indices where ids.contains(mails[index].id) {
            change(&mails[index])
        }
        do {
            for (id, group) in Dictionary(grouping: list, by: { $0.account }) {
                guard let account = accounts.first(where: { $0.id == id }) else { continue }
                persist(account.id)
                try await withIMAP(account) { imap in
                    for (folder, mails) in Dictionary(grouping: group, by: \.folder) {
                        try await imap.select(folder)
                        try await imap.store(mails.map(\.uid), flag, on)
                    }
                }
            }
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func withIMAP<T>(_ account: Account, _ work: (IMAP) async throws -> T) async throws -> T {
        let imap = try await IMAP(account: account, password: loadPassword(for: account.id))
        defer { imap.close() }
        return try await work(imap)
    }

    private func updateAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        saveAccounts()
    }

    private func fail(_ error: Error) {
        self.error = error.localizedDescription
        toast = error.localizedDescription
        failed += 1
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

    private func cacheFile(_ mail: Mail) -> URL {
        let folder = mail.account.map(directory) ?? FileManager.default.temporaryDirectory
        return folder.appending(path: mail.folder.replacingOccurrences(of: "/", with: "_") + "-" + String(mail.uid) + ".eml")
    }

    private func mailsFile(_ id: UUID) -> URL {
        directory(id).appending(path: "mails.json")
    }

    private func persist(_ id: UUID) {
        saveMails(mails.filter { $0.account == id }, id)
    }

    private func loadMails(_ id: UUID) -> [Mail] {
        guard let data = try? Data(contentsOf: mailsFile(id)), var list = try? JSONDecoder().decode([Mail].self, from: data) else { return [] }
        for index in list.indices {
            list[index].account = id
        }
        return list
    }

    private func saveMails(_ mails: [Mail], _ id: UUID) {
        try? JSONEncoder().encode(mails).write(to: mailsFile(id))
    }

    private func saveAccounts() {
        try? JSONEncoder().encode(accounts).write(to: accountsFile)
    }
}
