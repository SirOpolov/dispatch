import SwiftUI

struct ProviderForm: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var provider: Provider
    private let editing: Bool

    init(provider: Provider? = nil) {
        _provider = State(initialValue: provider ?? Provider())
        editing = provider != nil
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $provider.name)
            }
            Section("Incoming (IMAP)") {
                TextField("Server", text: $provider.imapHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", value: $provider.imapPort, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
            }
            Section {
                TextField("Server", text: $provider.smtpHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", value: $provider.smtpPort, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
            } header: {
                Text("Outgoing (SMTP)")
            } footer: {
                Text("Ports 993 and 465 use SSL/TLS, all others STARTTLS.")
            }
        }
        .navigationTitle(editing ? provider.name : String(localized: "Add Provider"))
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
                Button("Save") {
                    store.save(provider)
                    dismiss()
                }
                .disabled(provider.name.isEmpty || provider.imapHost.isEmpty || provider.smtpHost.isEmpty)
            }
        }
    }
}
