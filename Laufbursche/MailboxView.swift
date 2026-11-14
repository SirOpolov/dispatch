import SwiftUI

struct MailboxView: View {
    @Environment(Store.self) private var store
    @State private var filter: Filter?
    @State private var selected: String?
    @State private var column = NavigationSplitViewColumn.sidebar
    @State private var composing = false
    @State private var adding = false
    @State private var settings = false

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            sidebar
        } content: {
            if let filter {
                MessageList(filter: filter, selected: $selected) {
                    home()
                }
            } else {
                ContentUnavailableView("Ordner wählen", systemImage: "tray")
            }
        } detail: {
            if let selected, let mail = store.mails.first(where: { $0.id == selected }) {
                MessageView(mail: mail) {
                    self.selected = nil
                }
            } else {
                ContentUnavailableView("Keine E-Mail gewählt", systemImage: "envelope")
            }
        }
        .sheet(isPresented: $composing) {
            ComposeView()
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                AccountForm()
            }
        }
        .sheet(isPresented: $settings) {
            SettingsView()
        }
        .onChange(of: store.scope) {
            home()
        }
    }

    private func home() {
        selected = nil
        filter = nil
        column = .sidebar
    }

    private var sidebar: some View {
        List(selection: $filter) {
            Section {
                accountMenu
            }
            Section {
                Button {
                    composing = true
                } label: {
                    Label("E-Mail schreiben", systemImage: "square.and.pencil")
                        .font(.headline)
                }
            }
            if store.unified {
                Section("Alle Konten") {
                    row(.shared)
                    row(.unread)
                    row(.favorites)
                    row(.verified)
                }
            } else {
                Section("Posteingang") {
                    row(.unread)
                    row(.read)
                    row(.all)
                }
                Section {
                    row(.verified)
                    row(.favorites)
                    if let spam = store.current?.spam {
                        row(.folder(spam))
                    }
                    if let trash = store.current?.trash {
                        row(.folder(trash))
                    }
                }
                if let folders = store.current?.otherFolders, !folders.isEmpty {
                    Section("Ordner") {
                        ForEach(folders, id: \.self) { folder in
                            row(.folder(folder))
                        }
                    }
                }
            }
            if let error = store.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Postfach")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if store.syncing {
                    ProgressView()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    settings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .refreshable {
            await store.refresh()
        }
    }

    private var accountMenu: some View {
        Menu {
            if store.accounts.count > 1 {
                Button {
                    store.select(nil)
                } label: {
                    if store.unified {
                        Label("Alle Konten", systemImage: "checkmark")
                    } else {
                        Label("Alle Konten", systemImage: "person.2")
                    }
                }
                Divider()
            }
            ForEach(store.accounts) { account in
                Button {
                    store.select(account)
                } label: {
                    if !store.unified && account.id == store.current?.id {
                        Label(account.title, systemImage: "checkmark")
                    } else {
                        Text(account.title)
                    }
                }
            }
            Divider()
            Button {
                adding = true
            } label: {
                Label("Konto hinzufügen", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if store.unified {
                        Image(systemName: "person.2.fill")
                            .font(.subheadline)
                    } else {
                        Text(String(store.current?.title.prefix(1) ?? "?").uppercased())
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.tint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.unified ? "Alle Konten" : store.current?.title ?? "")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(store.unified ? store.accounts.map(\.email).joined(separator: ", ") : store.current?.email ?? "")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private func row(_ filter: Filter) -> some View {
        NavigationLink(value: filter) {
            Label(title(filter), systemImage: store.current?.icon(filter) ?? "folder")
        }
        .badge(filter == .read ? 0 : store.unread(filter))
    }

    private func title(_ filter: Filter) -> String {
        store.current?.title(filter) ?? ""
    }
}

struct MessageList: View {
    @Environment(Store.self) private var store
    @AppStorage("accent") private var accent = ""
    let filter: Filter
    @Binding var selected: String?
    let home: () -> Void
    @State private var editing = false
    @State private var marked = Set<String>()
    @State private var query = ""
    @State private var confirmAll = false

    var body: some View {
        let mails = visible
        let chosen = mails.filter { marked.contains($0.id) }
        Group {
            if editing {
                List(mails, selection: $marked) { mail in
                    row(mail)
                }
                .environment(\.editMode, .constant(.active))
            } else {
                List(mails, selection: $selected) { mail in
                    NavigationLink(value: mail.id) {
                        row(mail)
                    }
                    .contextMenu {
                        senderMenu(mail)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                await store.delete([mail])
                            }
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task {
                                await store.setSeen([mail], !mail.seen)
                            }
                        } label: {
                            Label(mail.seen ? "Ungelesen" : "Gelesen", systemImage: mail.seen ? "envelope.badge" : "envelope.open")
                        }
                        .tint(themeColor(accent))
                        Button {
                            Task {
                                await store.setFlagged([mail], !mail.flagged)
                            }
                        } label: {
                            Label(mail.flagged ? "Kein Favorit" : "Favorit", systemImage: mail.flagged ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                }
            }
        }
        .overlay {
            if mails.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Keine E-Mails" : "Keine Treffer", systemImage: store.current?.icon(filter) ?? "tray")
            }
        }
        .navigationTitle(store.current?.title(filter) ?? "")
        .modifier(Search(enabled: store.unified, query: $query))
        .refreshable {
            await store.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    home()
                } label: {
                    Image(systemName: store.unified ? "person.2.circle" : "person.crop.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if editing {
                    Button("Fertig") {
                        editing = false
                        marked = []
                    }
                } else {
                    Menu {
                        Button {
                            editing = true
                        } label: {
                            Label("Auswählen", systemImage: "checkmark.circle")
                        }
                        Button {
                            Task {
                                await store.setSeen(mails.filter { !$0.seen }, true)
                            }
                        } label: {
                            Label("Alle als gelesen markieren", systemImage: "envelope.open")
                        }
                        .disabled(!mails.contains { !$0.seen })
                        if filter != .favorites {
                            Button(role: .destructive) {
                                confirmAll = true
                            } label: {
                                Label("Alle löschen", systemImage: "trash")
                            }
                            .disabled(!mails.contains { !$0.flagged })
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            if editing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(chosen.count == mails.count && !mails.isEmpty ? "Keine" : "Alle") {
                        marked = chosen.count == mails.count ? [] : Set(mails.map(\.id))
                    }
                    Spacer()
                    Button {
                        finish { await store.setSeen(chosen, chosen.contains { !$0.seen }) }
                    } label: {
                        Image(systemName: chosen.contains { !$0.seen } ? "envelope.open" : "envelope.badge")
                    }
                    .disabled(chosen.isEmpty)
                    Button {
                        finish { await store.setFlagged(chosen, chosen.contains { !$0.flagged }) }
                    } label: {
                        Image(systemName: chosen.contains { !$0.flagged } ? "star" : "star.slash")
                    }
                    .disabled(chosen.isEmpty)
                    Button(role: .destructive) {
                        finish { await store.delete(chosen) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
        .confirmationDialog(mailCount(mails.filter { !$0.flagged }.count) + " löschen?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task {
                    await store.delete(mails.filter { !$0.flagged })
                }
            }
        } message: {
            Text("Favoriten bleiben erhalten. Im Papierkorb wird endgültig gelöscht.")
        }
        .onChange(of: filter) {
            editing = false
            marked = []
            query = ""
        }
    }

    private var visible: [Mail] {
        store.list(filter)
            .filter { query.isEmpty || $0.subject.localizedCaseInsensitiveContains(query) || $0.from.localizedCaseInsensitiveContains(query) || $0.to.localizedCaseInsensitiveContains(query) }
            .sorted { $0.date > $1.date }
    }

    private func row(_ mail: Mail) -> some View {
        MailRow(mail: mail, account: store.unified ? store.account(of: mail)?.title : nil, trusted: store.isTrusted(mail))
    }

    @ViewBuilder
    private func senderMenu(_ mail: Mail) -> some View {
        let sender = address(mail.from).lowercased()
        let domain = "*@" + (sender.split(separator: "@").last.map(String.init) ?? "")
        Section(sender) {
            Button {
                store.trust(sender)
            } label: {
                Label("Absender vertrauen", systemImage: "checkmark.seal")
            }
            Button {
                store.trust(domain)
            } label: {
                Label("Domain vertrauen (" + domain + ")", systemImage: "checkmark.seal.fill")
            }
            Button(role: .destructive) {
                Task {
                    await store.block(sender)
                }
            } label: {
                Label("Absender ist Spam", systemImage: "xmark.bin")
            }
            Button(role: .destructive) {
                Task {
                    await store.block(domain)
                }
            } label: {
                Label("Domain ist Spam (" + domain + ")", systemImage: "xmark.bin.fill")
            }
        }
    }

    private func finish(_ action: @escaping () async -> Void) {
        editing = false
        marked = []
        Task {
            await action()
        }
    }
}

struct Search: ViewModifier {
    let enabled: Bool
    @Binding var query: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $query, prompt: "In allen Konten suchen")
        } else {
            content
        }
    }
}

struct MailRow: View {
    let mail: Mail
    var account: String?
    var trusted = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(from: mail.from)
                .overlay(alignment: .topLeading) {
                    if !mail.seen {
                        Circle()
                            .fill(.tint)
                            .frame(width: 12, height: 12)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2)
                            }
                            .offset(x: -3, y: -3)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(senderName(mail.from))
                        .font(.headline.weight(mail.seen ? .regular : .semibold))
                        .lineLimit(1)
                    if trusted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    if mail.flagged {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Text(shortDate(mail.date))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Text(mail.subject.isEmpty ? "(Kein Betreff)" : mail.subject)
                    .font(.subheadline)
                    .foregroundStyle(mail.seen ? Color.secondary : Color.primary)
                    .lineLimit(2)
                if let account {
                    Text(account)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func shortDate(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits))
    }
}
