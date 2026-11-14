import SwiftUI

struct ComposeView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var to: String
    @State private var subject: String
    @State private var text: String
    @State private var sending = false
    @State private var failure: String?

    init(to: String = "", subject: String = "", text: String = "") {
        _to = State(initialValue: to)
        _subject = State(initialValue: subject)
        _text = State(initialValue: text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Von", value: store.current?.email ?? "")
                    TextField("An", text: $to)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Betreff", text: $subject)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 320)
                }
            }
            .navigationTitle("Neue E-Mail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button {
                            send()
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .disabled(to.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .alert("Senden fehlgeschlagen", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func send() {
        sending = true
        Task {
            do {
                try await store.send(to: to, subject: subject, body: text)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
            sending = false
        }
    }
}
