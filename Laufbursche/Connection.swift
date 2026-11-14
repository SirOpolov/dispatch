import Foundation

struct MailError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

class Connection {
    private let task: URLSessionStreamTask
    private var buffer = Data()

    init(host: String, port: Int, tls: Bool) {
        task = URLSession.shared.streamTask(withHostName: host, port: port)
        task.resume()
        if tls {
            task.startSecureConnection()
        }
    }

    func startTLS() {
        task.startSecureConnection()
    }

    func close() {
        task.cancel()
    }

    func send(_ text: String) async throws {
        try await write(Data(text.utf8))
    }

    func write(_ data: Data) async throws {
        try await task.write(data, timeout: 30)
    }

    func line() async throws -> Data {
        let separator = Data("\r\n".utf8)
        while true {
            if let range = buffer.range(of: separator) {
                let line = Data(buffer[buffer.startIndex..<range.lowerBound])
                buffer = Data(buffer[range.upperBound...])
                return line
            }
            try await fill()
        }
    }

    func bytes(_ count: Int) async throws -> Data {
        while buffer.count < count {
            try await fill()
        }
        let data = Data(buffer.prefix(count))
        buffer = Data(buffer.dropFirst(count))
        return data
    }

    private func fill() async throws {
        let (data, end) = try await task.readData(ofMinLength: 1, maxLength: 65536, timeout: 30)
        if let data, !data.isEmpty {
            buffer.append(data)
            return
        }
        if end {
            throw MailError("Verbindung vom Server getrennt")
        }
    }
}
