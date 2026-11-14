import Foundation

class SMTP {
    private let connection: Connection

    init(account: Account, password: String) async throws {
        let tls = account.smtpPort == 465
        connection = Connection(host: account.smtpHost, port: account.smtpPort, tls: tls)
        try await expect()
        try await send("EHLO laufbursche")
        if !tls {
            try await send("STARTTLS")
            connection.startTLS()
            try await send("EHLO laufbursche")
        }
        let token = Data(("\0" + account.login + "\0" + password).utf8).base64EncodedString()
        try await send("AUTH PLAIN " + token)
    }

    func close() {
        connection.close()
    }

    func deliver(from: String, to recipients: [String], message: Data) async throws {
        try await send("MAIL FROM:<" + from + ">")
        for recipient in recipients {
            try await send("RCPT TO:<" + recipient + ">")
        }
        try await send("DATA")
        try await connection.write(message + Data("\r\n.\r\n".utf8))
        try await expect()
        try? await send("QUIT")
    }

    private func send(_ command: String) async throws {
        try await connection.send(command + "\r\n")
        try await expect()
    }

    private func expect() async throws {
        var line = ""
        repeat {
            line = String(decoding: try await connection.line(), as: UTF8.self)
        } while line.count > 3 && Array(line)[3] == "-"
        guard line.first == "2" || line.first == "3" else {
            throw MailError(line)
        }
    }
}

func encodeWord(_ text: String) -> String {
    if text.allSatisfy(\.isASCII) {
        return text
    }
    return "=?UTF-8?B?" + Data(text.utf8).base64EncodedString() + "?="
}

func addresses(_ text: String) -> [String] {
    text.split { $0 == "," || $0 == ";" }.map { address(String($0)) }.filter { $0.contains("@") }
}

func message(account: Account, draft: Draft) -> Data {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
    let domain = account.email.split(separator: "@").last.map(String.init) ?? "localhost"
    let sender = account.name.isEmpty ? account.email : (account.name.allSatisfy(\.isASCII) ? quote(account.name) : encodeWord(account.name)) + " <" + account.email + ">"
    var lines = [
        "From: " + sender,
        "To: " + addresses(draft.to).joined(separator: ", "),
    ]
    if !addresses(draft.cc).isEmpty {
        lines.append("Cc: " + addresses(draft.cc).joined(separator: ", "))
    }
    lines += [
        "Subject: " + encodeWord(draft.subject),
        "Date: " + formatter.string(from: .now),
        "Message-ID: <" + UUID().uuidString + "@" + domain + ">",
        "MIME-Version: 1.0",
    ]
    if !draft.reply.isEmpty {
        lines += ["In-Reply-To: " + draft.reply, "References: " + draft.reply]
    }
    let text = [
        "Content-Type: text/plain; charset=utf-8",
        "Content-Transfer-Encoding: base64",
        "",
        Data(draft.body.utf8).base64EncodedString(options: .lineLength76Characters),
    ]
    if draft.attachments.isEmpty {
        lines += text
    } else {
        let boundary = "laufbursche-" + UUID().uuidString
        lines += ["Content-Type: multipart/mixed; boundary=\"" + boundary + "\"", "", "--" + boundary] + text
        for attachment in draft.attachments {
            let name = encodeWord(attachment.name.replacingOccurrences(of: "\"", with: "'"))
            lines += [
                "--" + boundary,
                "Content-Type: " + attachment.type + "; name=\"" + name + "\"",
                "Content-Disposition: attachment; filename=\"" + name + "\"",
                "Content-Transfer-Encoding: base64",
                "",
                attachment.data.base64EncodedString(options: .lineLength76Characters),
            ]
        }
        lines.append("--" + boundary + "--")
    }
    return Data(lines.joined(separator: "\r\n").utf8)
}
