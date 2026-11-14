import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme = 0
    @AppStorage("interval") private var interval = 60
    @State private var adding = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Darstellung") {
                    Picker("Erscheinungsbild", selection: $theme) {
                        Text("Auto").tag(0)
                        Text("Hell").tag(1)
                        Text("Dunkel").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Konten") {
                    ForEach(store.accounts) { account in
                        NavigationLink {
                            AccountForm(account: account)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.title)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for account in offsets.map({ store.accounts[$0] }) {
                            store.remove(account)
                        }
                    }
                    Button {
                        adding = true
                    } label: {
                        Label("Konto hinzufügen", systemImage: "plus")
                    }
                }
                Section {
                    Picker("Abrufen alle", selection: $interval) {
                        Text("30 Sekunden").tag(30)
                        Text("1 Minute").tag(60)
                        Text("5 Minuten").tag(300)
                        Text("15 Minuten").tag(900)
                    }
                    Button("Jetzt abrufen") {
                        Task {
                            await store.sync()
                        }
                    }
                    LabeledContent("Letzter Abruf", value: store.lastSync?.formatted(date: .omitted, time: .standard) ?? "–")
                    LabeledContent("E-Mails im Cache", value: String(store.mails.count))
                    LabeledContent("Spam-Ordner", value: store.current?.spam ?? "–")
                    LabeledContent("Papierkorb-Ordner", value: store.current?.trash ?? "–")
                    NavigationLink("Protokoll") {
                        List(Array(store.log.enumerated().reversed()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.caption.monospaced())
                        }
                        .navigationTitle("Protokoll")
                    }
                    Button("Cache leeren", role: .destructive) {
                        confirmClear = true
                    }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                } header: {
                    Text("Entwickler")
                } footer: {
                    Text("Abgerufen wird, solange die App geöffnet ist, und beim Zurückkehren in die App.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    AccountForm()
                }
            }
            .confirmationDialog("Lokalen Cache dieses Kontos leeren?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Leeren", role: .destructive) {
                    store.clearCache()
                    Task {
                        await store.sync()
                    }
                }
            }
        }
    }
}
