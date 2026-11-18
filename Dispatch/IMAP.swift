import Foundation

indirect enum Token {
    case atom(String)
    case text(Data)
    case list([Token])

    var string: String {
        switch self {
        case .atom(let value): value
        case .text(let data): String(decoding: data, as: UTF8.self)
        case .list: ""
        }
    }

    var data: Data {
        switch self {
        case .atom(let value): Data(value.utf8)
        case .text(let data): data
        case .list: Data()
        }
    }

    var items: [Token] {
        if case .list(let items) = self {
            return items
        }
        return []
    }
}

struct Parser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    mutating func responses() -> [[Token]] {
        var result: [[Token]] = []
        while index < bytes.count {
            var tokens: [Token] = []
            while index < bytes.count && bytes[index] != 13 && bytes[index] != 10 {
                if bytes[index] == 32 {
                    index += 1
                    continue
                }
                tokens.append(token())
            }
            while index < bytes.count && (bytes[index] == 13 || bytes[index] == 10) {
                index += 1
            }
            if !tokens.isEmpty {
                result.append(tokens)
            }
        }
        return result
    }

    private mutating func token() -> Token {
        switch bytes[index] {
        case 40:
            return list()
        case 34:
            return quoted()
        case 123:
            return literal()
        default:
            return atom()
        }
    }

    private mutating func list() -> Token {
        index += 1
        var items: [Token] = []
        while index < bytes.count && bytes[index] != 41 {
            if bytes[index] == 32 || bytes[index] == 13 || bytes[index] == 10 {
                index += 1
                continue
            }
            items.append(token())
        }
        index += 1
        return .list(items)
    }

    private mutating func quoted() -> Token {
        index += 1
        var data: [UInt8] = []
        while index < bytes.count && bytes[index] != 34 {
            if bytes[index] == 92 {
                index += 1
            }
            if index < bytes.count {
                data.append(bytes[index])
            }
            index += 1
        }
        index += 1
        return .text(Data(data))
    }

    private mutating func literal() -> Token {
        index += 1
        var size = 0
        while index < bytes.count && bytes[index] != 125 {
            if bytes[index] >= 48 && bytes[index] <= 57 {
                size = size * 10 + Int(bytes[index]) - 48
            }
            index += 1
        }
        index += 1
        if index < bytes.count && bytes[index] == 13 {
            index += 1
        }
        if index < bytes.count && bytes[index] == 10 {
            index += 1
        }
        let end = min(index + size, bytes.count)
        let data = Data(bytes[index..<end])
        index = end
        return .text(data)
    }

    private mutating func atom() -> Token {
        let start = index
        var depth = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 91 {
                depth += 1
            } else if byte == 93 {
                depth -= 1
            } else if depth <= 0 && (byte == 32 || byte == 40 || byte == 41 || byte == 13 || byte == 10) {
                break
            }
            index += 1
        }
        if index == start {
            index += 1
        }
        return .atom(String(decoding: bytes[start..<index], as: UTF8.self))
    }
}

func fetches(_ response: Data) -> [[String: Token]] {
    var parser = Parser(response)
    return parser.responses().compactMap { tokens in
        guard tokens.count >= 4, tokens[2].string.uppercased() == "FETCH" else { return nil }
        let items = tokens[3].items
        var result: [String: Token] = [:]
        var index = 0
        while index + 1 < items.count {
            var key = items[index].string.uppercased()
            if key.hasPrefix("BODY[") {
                key = "BODY"
            }
            result[key] = items[index + 1]
            index += 2
        }
        return result
    }
}

func hasFlag(_ flags: Token?, _ name: String) -> Bool {
    flags?.items.contains { $0.string.lowercased() == name } ?? false
}

func isSeen(_ flags: Token?) -> Bool {
    hasFlag(flags, "\\seen")
}

struct Folders {
    var spam: String?
    var trash: String?
    var sent: String?
    var all: [String]
}

func quote(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

class IMAP {
    private let connection: Connection
    private var counter = 0

    init(account: Account, password: String) async throws {
        let tls = account.imapPort == 993
        connection = Connection(host: account.imapHost, port: account.imapPort, tls: tls)
        _ = try await connection.line()
        if !tls {
            try await command("STARTTLS")
            connection.startTLS()
        }
        try await command("LOGIN " + quote(account.login) + " " + quote(password))
    }

    func close() {
        connection.close()
    }

    @discardableResult
    func command(_ text: String) async throws -> Data {
        let tag = nextTag()
        try await connection.send(tag + " " + text + "\r\n")
        return try await finish(tag)
    }

    func append(_ message: Data, to folder: String) async throws {
        let tag = nextTag()
        try await connection.send(tag + " APPEND " + quote(folder) + " (\\Seen) {" + String(message.count) + "}\r\n")
        let line = try await connection.line()
        guard line.first == 43 else {
            throw MailError(String(decoding: line, as: UTF8.self))
        }
        try await connection.write(message + Data("\r\n".utf8))
        try await finish(tag)
    }

    private func nextTag() -> String {
        counter += 1
        return "A" + String(counter)
    }

    @discardableResult
    private func finish(_ tag: String) async throws -> Data {
        let prefix = Data((tag + " ").utf8)
        let newline = Data("\r\n".utf8)
        var response = Data()
        while true {
            var line = try await connection.line()
            if line.starts(with: prefix) {
                let status = String(decoding: line.dropFirst(prefix.count), as: UTF8.self)
                if !status.uppercased().hasPrefix("OK") {
                    throw MailError(status)
                }
                return response
            }
            response.append(line)
            response.append(newline)
            while let size = literalSize(line) {
                response.append(try await connection.bytes(size))
                line = try await connection.line()
                response.append(line)
                response.append(newline)
            }
        }
    }

    func folders() async throws -> Folders {
        var parser = Parser(try await command("LIST \"\" \"*\""))
        let entries = parser.responses().filter { $0.count >= 5 && $0[1].string.uppercased() == "LIST" }.map { tokens in
            let name = tokens[4].string
            let delimiter = tokens[3].string
            let last = delimiter.isEmpty || delimiter == "NIL" ? name : name.components(separatedBy: delimiter).last ?? name
            return (attributes: tokens[2].items.map { $0.string.lowercased() }, name: name, last: last.lowercased())
        }
        func find(_ attribute: String, _ names: [String]) -> String? {
            entries.first { $0.attributes.contains(attribute) }?.name ?? entries.first { names.contains($0.last) }?.name
        }
        return Folders(
            spam: find("\\junk", ["spam", "junk", "junk e-mail", "junk-e-mail", "spamverdacht"]),
            trash: find("\\trash", ["trash", "papierkorb", "deleted", "deleted items", "deleted messages", "gel&apy-scht"]),
            sent: find("\\sent", ["sent", "gesendet", "gesendete objekte", "gesendete elemente", "sent items", "sent messages"]),
            all: entries.filter { !$0.attributes.contains("\\noselect") && !$0.attributes.contains("\\nonexistent") }.map(\.name)
        )
    }

    func select(_ folder: String) async throws {
        try await command("SELECT " + quote(folder))
    }

    func search() async throws -> [Int] {
        var parser = Parser(try await command("UID SEARCH ALL"))
        return parser.responses()
            .filter { $0.count > 1 && $0[1].string.uppercased() == "SEARCH" }
            .flatMap { $0.dropFirst(2).compactMap { Int($0.string) } }
    }

    func flags() async throws -> [Int: (seen: Bool, flagged: Bool)] {
        var result: [Int: (seen: Bool, flagged: Bool)] = [:]
        for item in fetches(try await command("UID FETCH 1:* (UID FLAGS)")) {
            if let uid = Int(item["UID"]?.string ?? "") {
                result[uid] = (isSeen(item["FLAGS"]), hasFlag(item["FLAGS"], "\\flagged"))
            }
        }
        return result
    }

    func headers(_ uids: [Int], folder: String) async throws -> [Mail] {
        var mails: [Mail] = []
        for start in stride(from: 0, to: uids.count, by: 100) {
            let chunk = uids[start..<min(start + 100, uids.count)].map(String.init).joined(separator: ",")
            let response = try await command("UID FETCH " + chunk + " (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM TO CC SUBJECT DATE MESSAGE-ID)])")
            for item in fetches(response) {
                guard let uid = Int(item["UID"]?.string ?? "") else { continue }
                let headers = parseHeaders(item["BODY"]?.data ?? Data())
                mails.append(Mail(
                    uid: uid,
                    folder: folder,
                    from: decodeWords(headers["from"] ?? ""),
                    to: decodeWords(headers["to"] ?? ""),
                    cc: decodeWords(headers["cc"] ?? ""),
                    subject: decodeWords(headers["subject"] ?? ""),
                    date: parseDate(headers["date"]) ?? .now,
                    seen: isSeen(item["FLAGS"]),
                    flagged: hasFlag(item["FLAGS"], "\\flagged"),
                    messageID: headers["message-id"] ?? ""
                ))
            }
        }
        return mails
    }

    func body(_ uid: Int) async throws -> Data {
        let response = try await command("UID FETCH " + String(uid) + " (UID BODY.PEEK[])")
        guard let body = fetches(response).compactMap({ $0["BODY"] }).first else {
            throw MailError(String(localized: "Email not found"))
        }
        return body.data
    }

    func store(_ uids: [Int], _ flag: String, _ on: Bool) async throws {
        try await command("UID STORE " + set(uids) + (on ? " +" : " -") + "FLAGS.SILENT (" + flag + ")")
    }

    func move(_ uids: [Int], to folder: String) async throws {
        do {
            try await command("UID MOVE " + set(uids) + " " + quote(folder))
        } catch {
            try await command("UID COPY " + set(uids) + " " + quote(folder))
            try await expunge(uids)
        }
    }

    func expunge(_ uids: [Int]) async throws {
        try await store(uids, "\\Deleted", true)
        try await command("EXPUNGE")
    }

    private func set(_ uids: [Int]) -> String {
        uids.map(String.init).joined(separator: ",")
    }

    private func literalSize(_ line: Data) -> Int? {
        guard line.last == 125, let open = line.lastIndex(of: 123) else { return nil }
        return Int(String(decoding: line[line.index(after: open)..<line.index(before: line.endIndex)], as: UTF8.self))
    }
}
