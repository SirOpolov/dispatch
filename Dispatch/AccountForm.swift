import SwiftUI

struct AccountForm: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var account: Account
    @State private var password = ""
    @State private var connecting = false
    @State private var failure: String?
    private let editing: Bool

    init(account: Account? = nil) {
        _account = State(initialValue: account ?? Account())
        editing = account != nil
    }

    var body: some View {
        Form {
            Section("Account") {
                TextField("Name", text: $account.name)
                TextField("Email", text: $account.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                SecureField(editing ? LocalizedStringKey("Password (unchanged)") : "Password", text: $password)
                    .textContentType(.password)
            }
            Section {
                ForEach(store.providers) { provider in
                    presetButton(provider)
                }
                if !account.imapHost.isEmpty && !account.smtpHost.isEmpty && !store.providers.contains(where: { $0.fits(account) }) {
                    Button("Save as Provider") {
                        store.save(Provider(name: account.imapHost, imapHost: account.imapHost, imapPort: account.imapPort, smtpHost: account.smtpHost, smtpPort: account.smtpPort))
                    }
                }
            } header: {
                Text("Fill In Servers")
            } footer: {
                Text("Manage providers in Settings.")
            }
            Section("Incoming (IMAP)") {
                TextField("Server", text: $account.imapHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", value: $account.imapPort, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
            }
            Section {
                TextField("Server", text: $account.smtpHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", value: $account.smtpPort, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                TextField("Username (default: email)", text: $account.user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Outgoing (SMTP)")
            } footer: {
                Text("Ports 993 and 465 use SSL/TLS, all others STARTTLS.")
            }
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } footer: {
                    Text("If the login is rejected: enable IMAP access at your provider and use an app password when two-factor authentication is on.")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: account.imapHost)
        .sensoryFeedback(.error, trigger: failure) { _, new in
            new != nil
        }
        .navigationTitle(editing ? account.title : String(localized: "Add Account"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !editing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if connecting {
                    ProgressView()
                } else {
                    Button("Connect") {
                        connect()
                    }
                    .disabled(account.email.isEmpty || account.imapHost.isEmpty || account.smtpHost.isEmpty || (password.isEmpty && !editing))
                }
            }
        }
    }

    private func presetButton(_ provider: Provider) -> some View {
        let active = provider.fits(account)
        return Button {
            withAnimation {
                account.imapHost = provider.imapHost
                account.imapPort = provider.imapPort
                account.smtpHost = provider.smtpHost
                account.smtpPort = provider.smtpPort
            }
        } label: {
            HStack {
                Text(provider.name)
                    .foregroundStyle(Color.primary)
                Spacer()
                if active {
                    Label("Filled In", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private func connect() {
        connecting = true
        failure = nil
        account.email = account.email.trimmingCharacters(in: .whitespaces)
        let secret = password.isEmpty ? loadPassword(for: account.id) : password
        Task {
            do {
                let checked = try await store.connect(account, password: secret)
                store.add(checked, password: secret)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
            connecting = false
        }
    }
}
