import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme = 0
    @AppStorage("interval") private var interval = 60
    @AppStorage("accent") private var accent = ""
    @AppStorage("icons") private var loadIcons = true
    @Environment(Icons.self) private var icons
    @State private var adding = false
    private let swatches = ["", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#FF3B30", "#34C759", "#30B0C7"]
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
                Section {
                    HStack(spacing: 10) {
                        ForEach(swatches, id: \.self) { hex in
                            Button {
                                accent = hex
                                store.confirm("Akzentfarbe geändert")
                            } label: {
                                Circle()
                                    .fill(hex.isEmpty ? defaultAccent : themeColor(hex))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if accent == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    ColorPicker("Eigene Farbe", selection: Binding(get: { themeColor(accent) }, set: { accent = hexString($0) }), supportsOpacity: false)
                    HStack {
                        Text("Hex")
                        TextField("#RRGGBB", text: $accent)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                    }
                    if !accent.isEmpty {
                        Button("Standardfarbe wiederherstellen") {
                            accent = ""
                            store.confirm("Standardfarbe wiederhergestellt")
                        }
                    }
                } header: {
                    Text("Akzentfarbe")
                }
                Section {
                    NavigationLink {
                        RuleList(spam: false)
                    } label: {
                        LabeledContent {
                            Text(String(store.trusted.count))
                        } label: {
                            Label("Vertrauenswürdig", systemImage: "checkmark.seal")
                        }
                    }
                    NavigationLink {
                        RuleList(spam: true)
                    } label: {
                        LabeledContent {
                            Text(String(store.blocked.count))
                        } label: {
                            Label("Spam", systemImage: "xmark.bin")
                        }
                    }
                } header: {
                    Text("Absender")
                } footer: {
                    Text("Vertrauenswürdige Absender landen in „Verifiziert“ und werden direkt mit HTML angezeigt. Spam-Absender werden automatisch in den Spam-Ordner verschoben. Tipp: E-Mail in der Liste gedrückt halten.")
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
                    Button {
                        Task {
                            await store.refresh()
                        }
                    } label: {
                        HStack {
                            Text("Jetzt abrufen")
                            Spacer()
                            if store.syncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(store.syncing)
                    LabeledContent("Letzter Abruf", value: store.lastSync?.formatted(date: .omitted, time: .standard) ?? "–")
                    LabeledContent("E-Mails im Cache", value: String(store.mails.count))
                    LabeledContent("Spam-Ordner", value: store.current?.spam ?? "–")
                    LabeledContent("Papierkorb-Ordner", value: store.current?.trash ?? "–")
                    LabeledContent("Gesendet-Ordner", value: store.current?.sent ?? "–")
                    LabeledContent("Ordner gesamt", value: String(store.current?.folders?.count ?? 0))
                    Toggle("Absender-Icons laden", isOn: $loadIcons)
                    Button("Icon-Cache leeren") {
                        icons.clearCache()
                        store.confirm("Icon-Cache geleert")
                    }
                    Button("Ordner neu suchen") {
                        store.rediscover()
                    }
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
                    Text("Bei geöffneter App wird im gewählten Abstand abgerufen. Im Hintergrund prüft iOS gelegentlich selbst und meldet neue E-Mails als Mitteilung.")
                }
            }
            .overlay(alignment: .bottom) {
                Toast()
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

struct RuleList: View {
    @Environment(Store.self) private var store
    @Environment(Icons.self) private var icons
    let spam: Bool
    @State private var entry = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("*@domain.de oder name@domain.de", text: $entry)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Hinzufügen", action: add)
                        .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("*@domain.de gilt für alle Adressen der Domain, name@domain.de nur für diese Adresse.")
            }
            Section {
                ForEach(rules, id: \.self) { rule in
                    if spam {
                        Label(rule, systemImage: "xmark.bin")
                    } else {
                        RuleRow(rule: rule)
                    }
                }
                .onDelete(perform: remove)
            } footer: {
                if !spam && !rules.isEmpty {
                    Text("Tippe auf ein Bild, um ein eigenes Icon festzulegen. Es ersetzt das automatisch geladene.")
                }
            }
        }
        .overlay(alignment: .bottom) {
            Toast()
        }
        .navigationTitle(spam ? "Spam-Absender" : "Vertrauenswürdig")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rules: [String] {
        spam ? store.blocked : store.trusted
    }

    private func add() {
        let rule = entry
        entry = ""
        if spam {
            Task {
                await store.block(rule)
            }
        } else {
            store.trust(rule)
        }
    }

    private func remove(_ offsets: IndexSet) {
        if spam {
            store.blocked.remove(atOffsets: offsets)
        } else {
            for rule in offsets.map({ store.trusted[$0] }) {
                icons.setCustom(nil, for: rule)
            }
            store.trusted.remove(atOffsets: offsets)
        }
        store.confirm("Entfernt")
    }
}

struct RuleRow: View {
    @Environment(Store.self) private var store
    @Environment(Icons.self) private var icons
    let rule: String
    @State private var item: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $item, matching: .images) {
                RuleIcon(rule: rule)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.circle.fill")
                            .font(.caption)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .tint)
                            .offset(x: 3, y: 3)
                    }
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule)
                Text(icons.custom[rule] == nil ? "Automatisches Icon" : "Eigenes Icon")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            if icons.custom[rule] != nil {
                Button {
                    icons.setCustom(nil, for: rule)
                    store.confirm("Eigenes Icon entfernt")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .onChange(of: item) {
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    icons.setCustom(image, for: rule)
                    store.confirm("Icon gespeichert")
                } else {
                    store.toast = "Bild konnte nicht geladen werden"
                    store.failed += 1
                }
                self.item = nil
            }
        }
    }
}
