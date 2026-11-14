import SwiftUI

struct MailboxView: View {
    @Environment(Store.self) private var store
    @State private var filter: Filter?
    @State private var selected: String?
    @State private var composing = false
    @State private var adding = false
    @State private var settings = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if let filter {
                MessageList(filter: filter, selected: $selected)
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
        .onChange(of: store.current?.id) {
            filter = nil
            selected = nil
        }
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
            Section("Posteingang") {
                row(.unread)
                row(.read)
                row(.all)
            }
            Section {
                row(.spam)
                row(.trash)
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
            await store.sync()
        }
    }

    private var accountMenu: some View {
        Menu {
            ForEach(store.accounts) { account in
                Button {
                    store.currentID = account.id
                } label: {
                    if account.id == store.current?.id {
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
                Text(String(store.current?.title.prefix(1) ?? "?").uppercased())
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(accent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.current?.title ?? "")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(store.current?.email ?? "")
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
            Label(filter.title, systemImage: filter.icon)
        }
        .badge(store.count(filter))
    }
}

struct MessageList: View {
    @Environment(Store.self) private var store
    let filter: Filter
    @Binding var selected: String?

    var body: some View {
        let mails = store.mails.filter(filter.matches).sorted { $0.date > $1.date }
        List(mails, selection: $selected) { mail in
            NavigationLink(value: mail.id) {
                MailRow(mail: mail)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task {
                        await store.move(mail, to: .trash)
                    }
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    Task {
                        await store.setSeen(mail, !mail.seen)
                    }
                } label: {
                    Label(mail.seen ? "Ungelesen" : "Gelesen", systemImage: mail.seen ? "envelope.badge" : "envelope.open")
                }
                .tint(accent)
            }
        }
        .overlay {
            if mails.isEmpty {
                ContentUnavailableView("Keine E-Mails", systemImage: filter.icon)
            }
        }
        .navigationTitle(filter.title)
        .refreshable {
            await store.sync()
        }
    }
}

struct MailRow: View {
    let mail: Mail

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(mail.seen ? Color.clear : accent)
                .frame(width: 9, height: 9)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(senderName(mail.from))
                        .font(.headline.weight(mail.seen ? .regular : .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(shortDate(mail.date))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Text(mail.subject.isEmpty ? "(Kein Betreff)" : mail.subject)
                    .font(.subheadline)
                    .foregroundStyle(mail.seen ? Color.secondary : Color.primary)
                    .lineLimit(2)
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
