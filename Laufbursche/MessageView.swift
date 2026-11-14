import SwiftUI
import WebKit

struct MessageView: View {
    @Environment(Store.self) private var store
    let mail: Mail
    let close: () -> Void
    @State private var content: MailContent?
    @State private var loading = true
    @State private var render = false
    @State private var replying = false

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
                ContentUnavailableView("Laden fehlgeschlagen", systemImage: "exclamationmark.triangle", description: Text(store.error ?? ""))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    replying = true
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
        .sheet(isPresented: $replying) {
            ComposeView(to: address(mail.from), subject: replySubject, text: replyText)
        }
        .task(id: mail.id) {
            render = false
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
            Text(mail.subject.isEmpty ? "(Kein Betreff)" : mail.subject)
                .font(.title3.bold())
                .textSelection(.enabled)
            Text(mail.from)
                .font(.subheadline.weight(.medium))
            Text("An: " + mail.to)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
            Text(mail.date.formatted(date: .long, time: .shortened))
                .font(.caption)
                .foregroundStyle(Color.secondary)
            if let attachments = content?.attachments, !attachments.isEmpty {
                Label(attachments.joined(separator: ", "), systemImage: "paperclip")
                    .font(.caption)
                    .lineLimit(2)
            }
            Toggle("HTML und Bilder darstellen", isOn: $render)
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
                await store.setSeen(mail, false)
            }
        } label: {
            Label("Als ungelesen markieren", systemImage: "envelope.badge")
        }
        if mail.box == .inbox {
            moveButton("Als Spam markieren", "xmark.bin", .spam)
        }
        if mail.box == .spam {
            moveButton("Kein Spam", "tray.and.arrow.down", .inbox)
        }
        if mail.box == .trash {
            moveButton("Wiederherstellen", "tray.and.arrow.up", .inbox)
        }
        Button(role: .destructive) {
            close()
            Task {
                await store.move(mail, to: .trash)
            }
        } label: {
            Label(mail.box == .trash ? "Endgültig löschen" : "Löschen", systemImage: "trash")
        }
    }

    private func moveButton(_ title: String, _ icon: String, _ box: Box) -> some View {
        Button {
            close()
            Task {
                await store.move(mail, to: box)
            }
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private var replySubject: String {
        mail.subject.lowercased().hasPrefix("re:") ? mail.subject : "Re: " + mail.subject
    }

    private var replyText: String {
        let original = content.map(plainText) ?? ""
        let quoted = original.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        return "\n\nAm " + mail.date.formatted(date: .numeric, time: .shortened) + " schrieb " + mail.from + ":\n" + quoted
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
