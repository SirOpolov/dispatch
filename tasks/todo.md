# Todo

Build und Tests laufen nur in CI (GitHub Actions, macos-26): `xcodegen generate && xcodebuild test -scheme Dispatch -destination 'platform=iOS Simulator,name=iPhone 17'`. Neue Texte auf Englisch im Code, deutsche Übersetzung in `Dispatch/de.lproj/Localizable.strings` (und Schlüssel in `en.lproj`).

## Task 1: Einzelne Mail in beliebigen Ordner verschieben

**Description:** `Destination` bekommt `.folder(String)`, `Store.move` nutzt den Namen direkt als Ziel. In `MessageView.actions` ein Untermenü „Move to“ mit allen Ordnern des Kontos außer dem aktuellen. Dasselbe Untermenü im Kontextmenü der Mail-Liste.

**Acceptance criteria:**
- [ ] Mail aus dem Posteingang in einen eigenen Ordner verschieben, sie verschwindet aus der Liste und erscheint im Zielordner
- [ ] Der aktuelle Ordner taucht nicht als Ziel auf
- [ ] Toast „Moved to <Ordner>“ / „Verschoben nach <Ordner>“

**Verification:**
- [ ] CI grün
- [ ] Manuell: verschieben, Zielordner öffnen, im Webmail gegenprüfen

**Dependencies:** None

**Files likely touched:** `Dispatch/Models.swift`, `Dispatch/Store.swift`, `Dispatch/MessageView.swift`, `Dispatch/MailboxView.swift`, `Dispatch/*.lproj/Localizable.strings`

**Estimated scope:** M

## Task 2: Mehrere Mails verschieben

**Description:** Im Auswahlmodus von `MessageList` ein Ordner-Knopf in der Leiste unten (Menü mit den Ordnern), wie Gelesen/Favorit/Löschen.

**Acceptance criteria:**
- [ ] Mehrere Mails auswählen und gemeinsam in einen Ordner verschieben
- [ ] Knopf deaktiviert bei leerer Auswahl oder Mails aus verschiedenen Konten

**Verification:**
- [ ] CI grün
- [ ] Manuell: 3 Mails verschieben, in der Unified Inbox gemischt auswählen → Knopf aus

**Dependencies:** Task 1

**Files likely touched:** `Dispatch/MailboxView.swift`

**Estimated scope:** S

## Checkpoint 1
- [ ] CI grün
- [ ] Verschieben am Gerät geprüft
- [ ] Review mit dir

## Task 3: Lösch-Dauer pro Ordner einstellen

**Description:** `Account.retention: [String: Int]?` (Ordnername → Tage). Im ⋯-Menü der Ordneransicht „Auto-Delete…“ öffnet ein Formular: Schalter an/aus, Tage per Stepper und Zahlenfeld (1 bis 3650). Unread/Read/All setzen die Regel für INBOX, eigene Ordner, Spam und Papierkorb für sich selbst. Favorites, Verified und Unified Inbox zeigen den Eintrag nicht. Ein aktiver Ordner zeigt in der Seitenleiste ein kleines Timer-Symbol.

**Acceptance criteria:**
- [ ] Regel setzen, ändern und ausschalten, sie bleibt nach Neustart erhalten
- [ ] Footer erklärt: ältere Mails gehen beim Abruf in den Papierkorb, im Papierkorb endgültig, Favoriten bleiben
- [ ] Bestehende Konten laden ohne Fehler (Feld optional)

**Verification:**
- [ ] CI grün
- [ ] Manuell: Regel auf einem Ordner setzen, App neu starten, Regel noch da

**Dependencies:** None

**Files likely touched:** `Dispatch/Models.swift`, `Dispatch/Store.swift`, `Dispatch/MailboxView.swift`, `Dispatch/*.lproj/Localizable.strings`

**Estimated scope:** M

## Task 4: Abgelaufene Mails beim Abruf löschen

**Description:** Freie Funktion `expired(_ mails: [Mail], days: Int, now: Date) -> [Mail]`: älter als `days`, nicht favorisiert. In `Store.download` nach dem Abruf jedes Ordners mit Regel: Treffer per `IMAP.move` in den Papierkorb, im Papierkorb oder ohne Papierkorb per `expunge` endgültig. Lokale Liste und Cache entsprechend bereinigen, Protokolleintrag mit Anzahl.

**Acceptance criteria:**
- [ ] Mails älter als X Tage verschwinden beim nächsten Abruf aus dem Ordner und liegen im Papierkorb
- [ ] Favoriten bleiben, jüngere Mails bleiben
- [ ] Läuft auch beim Hintergrundabruf
- [ ] Unit-Test für `expired` (Grenze genau X Tage, Favorit, jünger)

**Verification:**
- [ ] CI grün inkl. neuem Test
- [ ] Manuell: Regel 1 Tag auf Testordner mit alten Mails, Abruf, Papierkorb prüfen

**Dependencies:** Task 3

**Files likely touched:** `Dispatch/Models.swift`, `Dispatch/Store.swift`, `DispatchTests/MailTests.swift`

**Estimated scope:** S

## Checkpoint 2
- [ ] CI grün
- [ ] Regel am Gerät geprüft, Favoriten bleiben
- [ ] Review mit dir

## Task 5: README und Release v1.1.0

**Description:** Feature-Liste um Verschieben und Auto-Delete ergänzen, `MARKETING_VERSION` auf 1.1, Tag `v1.1.0`.

**Acceptance criteria:**
- [ ] README nennt beide Funktionen
- [ ] Release v1.1.0 mit `Dispatch.ipa`

**Verification:**
- [ ] Release-Seite auf GitHub prüfen

**Dependencies:** Tasks 1 bis 4

**Files likely touched:** `README.md`, `project.yml`

**Estimated scope:** XS
