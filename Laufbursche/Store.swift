import BackgroundTasks
import Foundation
import Observation
import UserNotifications

let refreshTask = "de.greismicha.laufbursche.refresh"

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

    func list(_ filter: Filter) -> [Mail] {
        mails.filter { filter.matches($0, trash: current?.trash) }
    }

    func unread(_ filter: Filter) -> Int {
        list(filter).filter { !$0.seen }.count
    }

    func confirm(_ text: String) {
        toast = text
        done += 1
    }

    func connect(_ account: Account, password: String) async throws -> Account {
        var checked = account
        let imap = try await IMAP(account: account, password: password)
        defer { imap.close() }
        let folders = try await imap.folders()
        checked.spam = folders.spam
        checked.trash = folders.trash
        checked.sent = folders.sent
        checked.folders = folders.all
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
        confirm("Verbunden mit " + account.email)
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        deletePassword(for: account.id)
        try? FileManager.default.removeItem(at: directory(account.id))
        saveAccounts()
        currentID = accounts.first?.id
        note("Konto entfernt: " + account.email)
        confirm("Konto entfernt")
    }

    @discardableResult
    func sync() async -> Int {
        guard let account = current, !syncing else { return 0 }
        syncing = true
        defer { syncing = false }
        do {
            let fresh = try await download(account)
            if current?.id == account.id {
                error = nil
            }
            lastSync = .now
            note(account.email + ": " + String(fresh.count) + " neu")
            return fresh.count
        } catch {
            self.error = error.localizedDescription
            note("Fehler: " + error.localizedDescription)
            return 0
        }
    }

    func refresh() async {
        let count = await sync()
        if error == nil {
            confirm(count == 0 ? "Keine neuen E-Mails" : mailCount(count) + " neu")
        } else {
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
    }

    func raw(_ mail: Mail) async -> Data? {
        guard let account = current else { return nil }
        let file = cacheFile(mail, account.id)
        if let data = try? Data(contentsOf: file) {
            if !mail.seen {
                _ = await mark([mail], "\\Seen", true) { $0.seen = true }
            }
            return data
        }
        do {
            let data = try await withIMAP(account) { imap in
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
                saveMails(mails, account.id)
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
        let trash = current?.trash
        let permanent = list.filter { trash == nil || $0.folder == trash }
        let rest = list.filter { trash != nil && $0.folder != trash }
        await move(rest, to: trash, mailCount(rest.count) + " in den Papierkorb gelegt")
        await move(permanent, to: nil, mailCount(permanent.count) + " endgültig gelöscht")
    }

    func move(_ list: [Mail], to target: String?, _ text: String) async {
        guard let account = current, !list.isEmpty else { return }
        let ids = Set(list.map(\.id))
        mails.removeAll { ids.contains($0.id) }
        saveMails(mails, account.id)
        for mail in list {
            try? FileManager.default.removeItem(at: cacheFile(mail, account.id))
        }
        do {
            try await withIMAP(account) { imap in
                for (folder, group) in Dictionary(grouping: list, by: \.folder) {
                    try await imap.select(folder)
                    if let target, target != folder {
                        try await imap.move(group.map(\.uid), to: target)
                    } else {
                        try await imap.expunge(group.map(\.uid))
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
        guard let account = current else { return }
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
        confirm("Gesendet")
    }

    func clearCache() {
        guard let account = current else { return }
        try? FileManager.default.removeItem(at: directory(account.id))
        mails = []
        note("Cache geleert: " + account.email)
        confirm("Cache geleert")
    }

    func rediscover() {
        guard var account = current else { return }
        account.folders = nil
        updateAccount(account)
        confirm("Ordner werden neu gesucht")
        Task {
            await sync()
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
            let loaded = try await imap.headers(uids.filter { !known.contains($0) }, folder: folder)
            all += loaded
            fresh += loaded
        }
        saveMails(all, account.id)
        if current?.id == account.id {
            mails = all
        }
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
        guard let account = current, !list.isEmpty else { return false }
        let ids = Set(list.map(\.id))
        for index in mails.indices where ids.contains(mails[index].id) {
            change(&mails[index])
        }
        saveMails(mails, account.id)
        do {
            try await withIMAP(account) { imap in
                for (folder, group) in Dictionary(grouping: list, by: \.folder) {
                    try await imap.select(folder)
                    try await imap.store(group.map(\.uid), flag, on)
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

    private func cacheFile(_ mail: Mail, _ id: UUID) -> URL {
        directory(id).appending(path: mail.id.replacingOccurrences(of: "/", with: "_") + ".eml")
    }

    private func mailsFile(_ id: UUID) -> URL {
        directory(id).appending(path: "mails.json")
    }

    private func loadMails(_ id: UUID?) -> [Mail] {
        guard let id, let data = try? Data(contentsOf: mailsFile(id)) else { return [] }
        return (try? JSONDecoder().decode([Mail].self, from: data)) ?? []
    }

    private func saveMails(_ mails: [Mail], _ id: UUID) {
        try? JSONEncoder().encode(mails).write(to: mailsFile(id))
    }

    private func saveAccounts() {
        try? JSONEncoder().encode(accounts).write(to: accountsFile)
    }
}
