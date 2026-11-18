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
    @AppStorage("language") private var language = "en"
    @Environment(Icons.self) private var icons
    @State private var adding = false
    private let swatches = ["", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#FF3B30", "#34C759", "#30B0C7"]
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        Text("Auto").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Language", selection: $language) {
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Deutsch").tag("de")
                    }
                } footer: {
                    Text("Takes effect after restarting the app.")
                }
                Section {
                    HStack(spacing: 10) {
                        ForEach(swatches, id: \.self) { hex in
                            Button {
                                accent = hex
                                store.confirm(String(localized: "Accent color changed"))
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
                    ColorPicker("Custom Color", selection: Binding(get: { themeColor(accent) }, set: { accent = hexString($0) }), supportsOpacity: false)
                    HStack {
                        Text("Hex")
                        TextField("#RRGGBB", text: $accent)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                    }
                    if !accent.isEmpty {
                        Button("Restore Default Color") {
                            accent = ""
                            store.confirm(String(localized: "Default color restored"))
                        }
                    }
                } header: {
                    Text("Accent Color")
                }
                Section {
                    NavigationLink {
                        RuleList(spam: false)
                    } label: {
                        LabeledContent {
                            Text(String(store.trusted.count))
                        } label: {
                            Label("Trusted", systemImage: "checkmark.seal")
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
                    Text("Senders")
                } footer: {
                    Text("Trusted senders appear in “Verified” and are shown with HTML right away. Spam senders are moved to the spam folder automatically. Tip: press and hold an email in the list.")
                }
                Section("Accounts") {
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
                        Label("Add Account", systemImage: "plus")
                    }
                }
                Section {
                    Picker("Fetch Every", selection: $interval) {
                        Text("30 Seconds").tag(30)
                        Text("1 Minute").tag(60)
                        Text("5 Minutes").tag(300)
                        Text("15 Minutes").tag(900)
                    }
                    Button {
                        Task {
                            await store.refresh()
                        }
                    } label: {
                        HStack {
                            Text("Fetch Now")
                            Spacer()
                            if store.syncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(store.syncing)
                    LabeledContent("Last Fetch", value: store.lastSync?.formatted(date: .omitted, time: .standard) ?? "–")
                    LabeledContent("Cached Emails", value: String(store.mails.count))
                    LabeledContent("Spam Folder", value: store.current?.spam ?? "–")
                    LabeledContent("Trash Folder", value: store.current?.trash ?? "–")
                    LabeledContent("Sent Folder", value: store.current?.sent ?? "–")
                    LabeledContent("Total Folders", value: String(store.current?.folders?.count ?? 0))
                    Toggle("Load Sender Icons", isOn: $loadIcons)
                    Button("Clear Icon Cache") {
                        icons.clearCache()
                        store.confirm(String(localized: "Icon cache cleared"))
                    }
                    Button("Rediscover Folders") {
                        store.rediscover()
                    }
                    NavigationLink("Log") {
                        List(Array(store.log.enumerated().reversed()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.caption.monospaced())
                        }
                        .navigationTitle("Log")
                    }
                    Button("Clear Cache", role: .destructive) {
                        confirmClear = true
                    }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                } header: {
                    Text("Developer")
                } footer: {
                    Text("While the app is open, mail is fetched at the chosen interval. In the background, iOS checks now and then and reports new emails as notifications.")
                }
            }
            .overlay(alignment: .bottom) {
                Toast()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    AccountForm()
                }
            }
            .confirmationDialog("Clear the local cache of this account?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
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
                    TextField("*@domain.com or name@domain.com", text: $entry)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("*@domain.com applies to every address of the domain, name@domain.com only to that address.")
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
                    Text("Tap an image to set a custom icon. It replaces the one loaded automatically.")
                }
            }
        }
        .overlay(alignment: .bottom) {
            Toast()
        }
        .navigationTitle(spam ? LocalizedStringKey("Spam Senders") : "Trusted")
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
        store.confirm(String(localized: "Removed"))
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
                Text(icons.custom[rule] == nil ? LocalizedStringKey("Automatic Icon") : "Custom Icon")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            if icons.custom[rule] != nil {
                Button {
                    icons.setCustom(nil, for: rule)
                    store.confirm(String(localized: "Custom icon removed"))
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
                    store.confirm(String(localized: "Icon saved"))
                } else {
                    store.toast = String(localized: "Image could not be loaded")
                    store.failed += 1
                }
                self.item = nil
            }
        }
    }
}
