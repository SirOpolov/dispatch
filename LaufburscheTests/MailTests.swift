import XCTest
@testable import Laufbursche

final class MailTests: XCTestCase {
    func testEncodedWords() {
        XCTAssertEqual(decodeWords("=?UTF-8?Q?Gr=C3=BC=C3=9Fe?= aus Berlin"), "Grüße aus Berlin")
        XCTAssertEqual(decodeWords("=?utf-8?B?SGFsbG8=?= =?utf-8?B?IFdlbHQ=?="), "Hallo Welt")
        XCTAssertEqual(decodeWords("=?ISO-8859-1?Q?M=FCller?= <m@x.de>"), "Müller <m@x.de>")
    }

    func testHeaders() {
        let headers = parseHeaders(Data("From: Max <max@web.de>\r\nSubject: Ein langer\r\n Betreff\r\nDate: Fri, 14 Nov 2025 10:00:00 +0100\r\n".utf8))
        XCTAssertEqual(headers["subject"], "Ein langer Betreff")
        XCTAssertEqual(senderName(headers["from"] ?? ""), "Max")
        XCTAssertEqual(address(headers["from"] ?? ""), "max@web.de")
        XCTAssertNotNil(parseDate(headers["date"]))
    }

    func testMultipart() {
        let raw = """
        Content-Type: multipart/related; boundary="outer"\r
        \r
        --outer\r
        Content-Type: multipart/alternative; boundary=inner\r
        \r
        --inner\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: quoted-printable\r
        \r
        Sch=C3=B6ne Gr=\r
        =C3=BC=C3=9Fe\r
        --inner\r
        Content-Type: text/html; charset=utf-8\r
        Content-Transfer-Encoding: base64\r
        \r
        PHA+SGFsbG88L3A+PGltZyBzcmM9ImNpZDpsb2dvIj4=\r
        --inner--\r
        --outer\r
        Content-Type: image/png\r
        Content-ID: <logo>\r
        Content-Transfer-Encoding: base64\r
        \r
        iVBORw0KGgo=\r
        --outer\r
        Content-Type: application/pdf; name="Rechnung.pdf"\r
        Content-Disposition: attachment; filename="Rechnung.pdf"\r
        Content-Transfer-Encoding: base64\r
        \r
        JVBERi0=\r
        --outer--\r

        """
        let content = parseMail(Data(raw.utf8))
        XCTAssertEqual(content.text, "Schöne Grüße")
        XCTAssertEqual(content.html, "<p>Hallo</p><img src=\"cid:logo\">")
        XCTAssertEqual(content.attachments.map(\.name), ["Rechnung.pdf"])
        XCTAssertTrue(htmlDocument(content).contains("data:image/png;base64,iVBORw0KGgo="))
        XCTAssertEqual(stripHTML("<style>p{}</style><p>Hallo&nbsp;Welt</p>"), "Hallo Welt")
    }

    func testFetchResponse() {
        let response = Data("* 1 FETCH (UID 42 FLAGS (\\Seen) BODY[HEADER.FIELDS (FROM SUBJECT)] {17}\r\nSubject: Test\r\n\r\n)\r\n* 2 FETCH (FLAGS () UID 43 BODY[] \"x\")\r\n".utf8)
        let items = fetches(response)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0]["UID"]?.string, "42")
        XCTAssertTrue(isSeen(items[0]["FLAGS"]))
        XCTAssertEqual(parseHeaders(items[0]["BODY"]?.data ?? Data())["subject"], "Test")
        XCTAssertEqual(items[1]["UID"]?.string, "43")
        XCTAssertFalse(isSeen(items[1]["FLAGS"]))
    }

    func testFolderNames() {
        XCTAssertEqual(folderName("Gel&APY-scht"), "Gelöscht")
        XCTAssertEqual(folderName("INBOX.Entw&APw-rfe"), "Entwürfe")
        XCTAssertEqual(folderName("Tom &- Jerry"), "Tom & Jerry")
    }

    func testOutgoingMessage() {
        var account = Account()
        account.email = "ich@web.de"
        let draft = Draft(to: "Max <max@web.de>", subject: "Grüße", body: "Hallo", attachments: [Attachment(name: "a.txt", type: "text/plain", data: Data("x".utf8))])
        let content = parseMail(message(account: account, draft: draft))
        XCTAssertEqual(content.text, "Hallo")
        XCTAssertEqual(content.attachments.map(\.name), ["a.txt"])
        XCTAssertEqual(addresses("Max <max@web.de>, b@c.de; kein"), ["max@web.de", "b@c.de"])
    }

    func testSearch() {
        var parser = Parser(Data("* SEARCH 3 5 8\r\n".utf8))
        let numbers = parser.responses()[0].dropFirst(2).compactMap { Int($0.string) }
        XCTAssertEqual(numbers, [3, 5, 8])
    }
}
