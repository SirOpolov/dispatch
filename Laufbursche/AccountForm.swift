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
            Section("Konto") {
                TextField("Name", text: $account.name)
                TextField("E-Mail", text: $account.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                SecureField(editing ? "Passwort (unverändert)" : "Passwort", text: $password)
                    .textContentType(.password)
            }
            Section {
                presetButton("Strato", "imap.strato.de", 993, "smtp.strato.de", 465)
                presetButton("WEB.DE", "imap.web.de", 993, "smtp.web.de", 587)
            } header: {
                Text("Server vorbelegen")
            } footer: {
                Text("Bei WEB.DE muss IMAP im Webmail unter Einstellungen → POP3/IMAP freigeschaltet sein.")
            }
            Section("Empfang (IMAP)") {
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
                TextField("Benutzername (Standard: E-Mail)", text: $account.user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Versand (SMTP)")
            } footer: {
                Text("Port 993 und 465 nutzen SSL/TLS, alle anderen STARTTLS.")
            }
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: account.imapHost)
        .sensoryFeedback(.error, trigger: failure) { _, new in
            new != nil
        }
        .navigationTitle(editing ? account.title : "Konto hinzufügen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !editing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if connecting {
                    ProgressView()
                } else {
                    Button("Verbinden") {
                        connect()
                    }
                    .disabled(account.email.isEmpty || account.imapHost.isEmpty || account.smtpHost.isEmpty || (password.isEmpty && !editing))
                }
            }
        }
    }

    private func presetButton(_ title: String, _ imapHost: String, _ imapPort: Int, _ smtpHost: String, _ smtpPort: Int) -> some View {
        let active = account.imapHost == imapHost && account.imapPort == imapPort && account.smtpHost == smtpHost && account.smtpPort == smtpPort
        return Button {
            withAnimation {
                account.imapHost = imapHost
                account.imapPort = imapPort
                account.smtpHost = smtpHost
                account.smtpPort = smtpPort
            }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if active {
                    Label("Eingetragen", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(accent)
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
