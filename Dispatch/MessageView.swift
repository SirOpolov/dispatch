import QuickLook
import SwiftUI
import WebKit

struct MessageView: View {
    @Environment(Store.self) private var store
    let mail: Mail
    let close: () -> Void
    @State private var content: MailContent?
    @State private var loading = true
    @State private var render = false
    @State private var draft: Draft?
    @State private var preview: URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let content {
                if render {
                    HTMLView(html: htmlDocument(content))
                } else {
                    ScrollView {
                        Text(plainText(content))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            } else if loading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView("Loading Failed", systemImage: "exclamationmark.triangle", description: Text(store.error ?? ""))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.setFlagged([mail], !mail.flagged)
                    }
                } label: {
                    Image(systemName: mail.flagged ? "star.fill" : "star")
                }
                Menu {
                    Button {
                        draft = reply(all: false)
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    Button {
                        draft = reply(all: true)
                    } label: {
                        Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                    }
                    Button {
                        draft = forward
                    } label: {
                        Label("Forward", systemImage: "arrowshape.turn.up.right")
                    }
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                Menu {
                    actions
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(item: $draft) { draft in
            ComposeView(draft: draft)
        }
        .quickLookPreview($preview)
        .task(id: mail.id) {
            render = store.isTrusted(mail)
            content = nil
            loading = true
            if let raw = await store.raw(mail) {
                content = parseMail(raw)
            }
            loading = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mail.subject.isEmpty ? String(localized: "(No Subject)") : mail.subject)
                .font(.title3.bold())
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Avatar(from: mail.from, size: 44)
                Text(mail.from)
                    .font(.subheadline.weight(.medium))
                if store.isTrusted(mail) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.tint)
                }
            }
            if store.unified, let owner {
                Text("Account: \(owner.title)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
            }
            Text(String(localized: "To: \(mail.to)") + (mail.cc.isEmpty ? "" : "\nCc: " + mail.cc))
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .lineLimit(3)
            Text(mail.date.formatted(date: .long, time: .shortened))
                .font(.caption)
                .foregroundStyle(Color.secondary)
            if let attachments = content?.attachments, !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            Button {
                                open(attachment)
                            } label: {
                                Label(attachment.name, systemImage: "paperclip")
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Toggle("Show HTML and Images", isOn: $render)
                .font(.subheadline)
                .disabled(content == nil)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private var actions: some View {
        Button {
            close()
            Task {
                await store.setSeen([mail], false)
            }
        } label: {
            Label("Mark as Unread", systemImage: "envelope.badge")
        }
        if owner?.spam != nil && mail.inbox {
            moveButton("Mark as Spam", "xmark.bin", .spam, String(localized: "Moved to spam"))
        }
        if mail.folder == owner?.spam {
            moveButton("Not Spam", "tray.and.arrow.down", .inbox, String(localized: "Moved to inbox"))
        }
        if mail.folder == owner?.trash {
            moveButton("Restore", "tray.and.arrow.up", .inbox, String(localized: "Restored"))
        }
        Section(address(mail.from).lowercased()) {
            Button {
                store.trust(address(mail.from))
                render = true
            } label: {
                Label("Trust Sender", systemImage: "checkmark.seal")
            }
            .disabled(store.isTrusted(mail))
            Button(role: .destructive) {
                close()
                Task {
                    await store.block(address(mail.from))
                }
            } label: {
                Label("Sender Is Spam", systemImage: "xmark.bin")
            }
        }
        Button(role: .destructive) {
            close()
            Task {
                await store.delete([mail])
            }
        } label: {
            Label(mail.folder == owner?.trash ? LocalizedStringKey("Delete Permanently") : "Delete", systemImage: "trash")
        }
    }

    private var owner: Account? {
        store.account(of: mail)
    }

    private func moveButton(_ title: LocalizedStringKey, _ icon: String, _ target: Destination, _ text: String) -> some View {
        Button {
            close()
            Task {
                await store.move([mail], to: target, text)
            }
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func open(_ attachment: Attachment) {
        let folder = FileManager.default.temporaryDirectory.appending(path: attachment.id.uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: attachment.name.replacingOccurrences(of: "/", with: "_"))
        do {
            try attachment.data.write(to: file)
            preview = file
        } catch {
            store.toast = String(localized: "Attachment could not be opened")
            store.failed += 1
        }
    }

    private var original: String {
        content.map(plainText) ?? ""
    }

    private func reply(all: Bool) -> Draft {
        let own = owner?.email.lowercased() ?? ""
        let others = addresses(mail.to + "," + mail.cc).filter { $0.lowercased() != own }
        let quoted = original.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        return Draft(
            account: mail.account,
            to: address(mail.from),
            cc: all ? others.joined(separator: ", ") : "",
            subject: mail.subject.lowercased().hasPrefix("re:") ? mail.subject : "Re: " + mail.subject,
            body: "\n\n" + String(localized: "On \(mail.date.formatted(date: .numeric, time: .shortened)), \(mail.from) wrote:") + "\n" + quoted,
            reply: mail.messageID
        )
    }

    private var forward: Draft {
        let lines = [
            "",
            "",
            String(localized: "---------- Forwarded message ----------"),
            String(localized: "From: \(mail.from)"),
            String(localized: "Date: \(mail.date.formatted(date: .long, time: .shortened))"),
            String(localized: "Subject: \(mail.subject)"),
            String(localized: "To: \(mail.to)"),
            "",
            original,
        ]
        return Draft(
            account: mail.account,
            subject: mail.subject.lowercased().hasPrefix("fwd:") ? mail.subject : "Fwd: " + mail.subject,
            body: lines.joined(separator: "\n"),
            attachments: content?.attachments ?? []
        )
    }
}

struct HTMLView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
