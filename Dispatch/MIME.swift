import Foundation

struct MailContent {
    var text: String?
    var html: String?
    var images: [String: String] = [:]
    var attachments: [Attachment] = []
}

func parseMail(_ raw: Data) -> MailContent {
    var content = MailContent()
    walk(normalize(raw), into: &content)
    return content
}

func parseHeaders(_ data: Data) -> [String: String] {
    let text = decodeText(normalize(data), charset: "utf-8")
    var result: [String: String] = [:]
    var name = ""
    for line in text.components(separatedBy: "\n") {
        if line.first == " " || line.first == "\t" {
            if !name.isEmpty {
                result[name, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            }
        } else if let colon = line.firstIndex(of: ":") {
            name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if result[name] == nil {
                result[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            } else {
                name = ""
            }
        }
    }
    return result
}

func decodeWords(_ text: String) -> String {
    let joined = text.replacing(try! Regex(#"\?=\s+=\?"#), with: "?==?")
    return joined.replacing(try! Regex(#"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#)) { match -> String in
        let charset = String(match.output[1].substring ?? "").components(separatedBy: "*")[0]
        let mode = String(match.output[2].substring ?? "").uppercased()
        let value = String(match.output[3].substring ?? "")
        let data = mode == "B" ? base64(Data(value.utf8)) : quotedPrintable(Data(value.replacingOccurrences(of: "_", with: " ").utf8))
        return decodeText(data, charset: charset)
    }
}

func decodeText(_ data: Data, charset: String?) -> String {
    if let charset {
        let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        if encoding != kCFStringEncodingInvalidId {
            let converted = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
            if let text = String(data: data, encoding: converted) {
                return text
            }
        }
    }
    return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
}

func parseDate(_ value: String?) -> Date? {
    guard var text = value else { return nil }
    if let paren = text.firstIndex(of: "(") {
        text = String(text[..<paren])
    }
    if let comma = text.firstIndex(of: ",") {
        text = String(text[text.index(after: comma)...])
    }
    text = text.split(separator: " ").joined(separator: " ")
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in ["d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm:ss zzz", "d MMM yy HH:mm:ss Z"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: text) {
            return date
        }
    }
    return nil
}

func plainText(_ content: MailContent) -> String {
    if let text = content.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return text
    }
    return stripHTML(content.html ?? "")
}

func htmlDocument(_ content: MailContent) -> String {
    var html = content.html ?? "<pre style=\"white-space: pre-wrap; font: -apple-system-body;\">" + escapeHTML(content.text ?? "") + "</pre>"
    for (id, uri) in content.images {
        html = html.replacingOccurrences(of: "cid:" + id, with: uri)
    }
    return "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" + html
}

func stripHTML(_ html: String) -> String {
    var text = html.replacing(try! Regex(#"<(style|script|head)[^>]*>.*?</\1>"#).ignoresCase().dotMatchesNewlines(), with: "")
    text = text.replacing(try! Regex(#"<br[^>]*>|</p>|</div>|</tr>|</li>|</h[1-6]>"#).ignoresCase(), with: "\n")
    text = text.replacing(try! Regex(#"<[^>]+>"#), with: "")
    let entities = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß", "&euro;": "€", "&amp;": "&"]
    for (entity, value) in entities {
        text = text.replacingOccurrences(of: entity, with: value)
    }
    text = text.replacing(try! Regex(#"[ \t]+"#), with: " ")
    text = text.replacing(try! Regex(#"\s*\n\s*\n\s*"#), with: "\n\n")
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

func senderName(_ from: String) -> String {
    if let open = from.firstIndex(of: "<") {
        let name = from[..<open].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if !name.isEmpty {
            return name
        }
    }
    return address(from)
}

func address(_ from: String) -> String {
    if let open = from.firstIndex(of: "<"), let close = from.lastIndex(of: ">"), open < close {
        return String(from[from.index(after: open)..<close])
    }
    return from.trimmingCharacters(in: .whitespaces)
}

private func walk(_ data: Data, into content: inout MailContent) {
    let (headers, body) = split(data)
    let contentType = headers["content-type"]
    let type = contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? "text/plain"
    if type.hasPrefix("multipart/"), let boundary = parameter(contentType, "boundary") {
        for part in parts(body, boundary) {
            walk(part, into: &content)
        }
        return
    }
    let decoded = decodeBody(body, headers["content-transfer-encoding"])
    if type == "message/rfc822" {
        walk(normalize(decoded), into: &content)
        return
    }
    let disposition = headers["content-disposition"] ?? ""
    let filename = parameter(disposition, "filename") ?? parameter(contentType, "name")
    let id = headers["content-id"]?.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    if type.hasPrefix("image/"), let id {
        content.images[id] = "data:" + type + ";base64," + decoded.base64EncodedString()
    }
    if disposition.lowercased().hasPrefix("attachment") || (filename != nil && id == nil) {
        content.attachments.append(Attachment(name: decodeWords(filename ?? String(localized: "Attachment")), type: type, data: decoded))
        return
    }
    let charset = parameter(contentType, "charset")
    if type == "text/plain" && content.text == nil {
        content.text = decodeText(decoded, charset: charset)
    }
    if type == "text/html" && content.html == nil {
        content.html = decodeText(decoded, charset: charset)
    }
}

private func split(_ data: Data) -> (headers: [String: String], body: Data) {
    if data.first == 10 {
        return ([:], Data(data.dropFirst()))
    }
    guard let range = data.range(of: Data("\n\n".utf8)) else {
        return (parseHeaders(data), Data())
    }
    return (parseHeaders(Data(data[data.startIndex..<range.lowerBound])), Data(data[range.upperBound...]))
}

private func parts(_ body: Data, _ boundary: String) -> [Data] {
    let data = Data("\n".utf8) + body
    let marker = Data(("\n--" + boundary).utf8)
    var result: [Data] = []
    var start: Data.Index?
    var search = data.startIndex
    while let range = data.range(of: marker, in: search..<data.endIndex) {
        if let start, start <= range.lowerBound {
            result.append(Data(data[start..<range.lowerBound]))
        }
        start = nil
        let rest = data[range.upperBound...]
        if rest.starts(with: Data("--".utf8)) {
            return result
        }
        guard let newline = rest.firstIndex(of: 10) else {
            return result
        }
        start = newline + 1
        search = newline
    }
    if let start {
        result.append(Data(data[start...]))
    }
    return result
}

private func parameter(_ value: String?, _ name: String) -> String? {
    guard let value else { return nil }
    for piece in value.split(separator: ";").dropFirst() {
        let pair = piece.split(separator: "=", maxSplits: 1)
        guard pair.count == 2 else { continue }
        let key = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
        var result = pair[1].trimmingCharacters(in: .whitespaces)
        if result.count >= 2 && result.hasPrefix("\"") && result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
        }
        if key == name {
            return result
        }
        if key == name + "*", let range = result.range(of: "''") {
            return result[range.upperBound...].removingPercentEncoding
        }
    }
    return nil
}

private func decodeBody(_ body: Data, _ encoding: String?) -> Data {
    switch (encoding ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
    case "base64": base64(body)
    case "quoted-printable": quotedPrintable(body)
    default: body
    }
}

private func normalize(_ data: Data) -> Data {
    let bytes = [UInt8](data)
    var result: [UInt8] = []
    result.reserveCapacity(bytes.count)
    for index in bytes.indices {
        if bytes[index] == 13 && index + 1 < bytes.count && bytes[index + 1] == 10 {
            continue
        }
        result.append(bytes[index])
    }
    return Data(result)
}

private func base64(_ data: Data) -> Data {
    var clean = data.filter { $0 != 10 && $0 != 13 && $0 != 32 && $0 != 9 }
    while clean.count % 4 != 0 {
        clean.append(61)
    }
    return Data(base64Encoded: clean, options: .ignoreUnknownCharacters) ?? Data()
}

private func quotedPrintable(_ data: Data) -> Data {
    let bytes = [UInt8](data)
    var result: [UInt8] = []
    var index = 0
    while index < bytes.count {
        if bytes[index] == 61 {
            if index + 1 < bytes.count && bytes[index + 1] == 10 {
                index += 2
                continue
            }
            if index + 2 < bytes.count, let value = UInt8(String(decoding: bytes[index + 1...index + 2], as: UTF8.self), radix: 16) {
                result.append(value)
                index += 3
                continue
            }
        }
        result.append(bytes[index])
        index += 1
    }
    return Data(result)
}
