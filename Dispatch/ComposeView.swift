import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ComposeView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Draft
    @State private var sending = false
    @State private var importing = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var failure: String?

    init(draft: Draft = Draft()) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Von", selection: $draft.account) {
                        ForEach(store.accounts) { account in
                            Text(account.email)
                                .tag(Optional(account.id))
                        }
                    }
                    TextField("An", text: $draft.to)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Cc", text: $draft.cc)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Betreff", text: $draft.subject)
                }
                Section {
                    TextEditor(text: $draft.body)
                        .frame(minHeight: 280)
                }
                Section("Anhänge") {
                    ForEach(draft.attachments) { attachment in
                        HStack {
                            Label(attachment.name, systemImage: "paperclip")
                                .lineLimit(1)
                            Spacer()
                            Text(Int64(attachment.data.count).formatted(.byteCount(style: .file)))
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .onDelete { offsets in
                        draft.attachments.remove(atOffsets: offsets)
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Datei anhängen", systemImage: "doc.badge.plus")
                    }
                    PhotosPicker(selection: $photos, matching: .images) {
                        Label("Foto anhängen", systemImage: "photo.badge.plus")
                    }
                }
            }
            .navigationTitle(draft.subject.isEmpty ? "Neue E-Mail" : draft.subject)
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
                        .disabled(addresses(draft.to).isEmpty)
                    }
                }
            }
            .onAppear {
                if draft.account == nil {
                    draft.account = store.current?.id
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    if let data = try? Data(contentsOf: url) {
                        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        draft.attachments.append(Attachment(name: url.lastPathComponent, type: type, data: data))
                    }
                    if access {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
            .onChange(of: photos) {
                let items = photos
                guard !items.isEmpty else { return }
                photos = []
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8) {
                            draft.attachments.append(Attachment(name: "Foto-" + String(draft.attachments.count + 1) + ".jpg", type: "image/jpeg", data: jpeg))
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: draft.attachments.count)
            .sensoryFeedback(.error, trigger: failure) { _, new in
                new != nil
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
                try await store.send(draft)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
            sending = false
        }
    }
}
