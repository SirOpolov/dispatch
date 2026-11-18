# Implementation Plan: Rebrand, Englisch/Deutsch, eigene Anbieter, WEB.DE-Fix

## Overview

Laufbursche wird umbenannt (neuer Name offen), der GitHub-Account wechselt von GreisMicha zu SirOpolov, die App wird zweisprachig (Englisch Standard, Deutsch per Einstellung), Server-Vorlagen werden vom Nutzer anleg- und löschbar, der WEB.DE-Login wird repariert und die README bekommt das nightshift-Format inklusive Release-Workflow.

## Ist-Stand

- **Unified Inbox funktioniert im Code**: `Store.unified` lädt die Mails aller Konten (`reload`), `sync` holt alle Konten, `Filter.shared` zeigt alles außer Spam/Papierkorb/blockiert, Zeilen zeigen das Konto (`MailboxView.swift:359`), Suche nur dort aktiv (`MailboxView.swift:263`). Einschränkung: der Eintrag „Alle Konten“ erscheint erst ab 2 Konten, und solange WEB.DE nicht verbindet, gibt es praktisch nur eins.
- **WEB.DE-Verbindung**: `Store.connect` prüft IMAP *und* SMTP; scheitert eins, wird das Konto gar nicht gespeichert. Mögliche Ursachen, nach Wahrscheinlichkeit:
  1. IMAP/POP3 im WEB.DE-Webmail nicht freigeschaltet (Fehler „LOGIN failed“ o. ä.).
  2. 2-Faktor bei WEB.DE aktiv → normales Passwort wird abgelehnt, App-Passwort nötig.
  3. `EHLO laufbursche` ist kein FQDN; strenge Submission-Server lehnen das ab. RFC-konform wäre `EHLO [127.0.0.1]`.
  4. STARTTLS auf 587 über `URLSessionStreamTask.startSecureConnection` mitten im Stream.
  **Fehlermeldung vom Nutzer: „NO authentication …“.** Das ist die IMAP-Antwort auf `LOGIN` (SMTP würde mit `535` antworten). Der Server lehnt Benutzer/Passwort ab, Ursache 1 oder 2 ist damit am wahrscheinlichsten, nicht der Code. Ursache 3 betrifft erst den Versand danach.
- **Name „greismicha“** steckt in `project.yml` (bundleIdPrefix, Bundle-ID, BG-Task-ID), `Store.swift:6` und im Git-Remote.
- **Texte**: rund 300 deutsche String-Literale in 13 Dateien, auch außerhalb von Views (Store-Toasts, `Account.title`, `mailCount`, Fehler in IMAP/SMTP/MIME).

## Architecture Decisions

- **Umbenennung + Rebrand in einem Schritt.** Beide ändern die Bundle-ID. Eine neue Bundle-ID ist für iOS eine neue App: Konten, Cache und Schlüsselbund-Einträge der alten App sind weg (Passwörter neu eingeben). Einmal statt zweimal.
- **Neue Bundle-ID `de.siropolov.<name>`**, Keychain-Service bleibt ein fester String, wird auf den neuen Namen gesetzt (alte App wird ohnehin neu installiert).
- **Lokalisierung mit String Catalog** (`Localizable.xcstrings`), Quellsprache Englisch, Deutsch als Übersetzung. Keine Bibliothek.
  - Views: `Text("…")` nimmt LocalizedStringKey automatisch.
  - Nicht-View-Code: `String(localized:)`.
  - Sprachwahl in den Einstellungen: Picker System/English/Deutsch schreibt `AppleLanguages` in UserDefaults, Hinweis „wirkt nach Neustart“. Zusätzlich zeigt iOS automatisch die Sprache in Einstellungen → App, sobald zwei Lokalisierungen da sind. Kein Live-Umschalten (würde jede String-Suche über ein eigenes Bundle erfordern).
- **Anbieter-Vorlagen** als `struct Provider: Codable, Identifiable` (name, imapHost, imapPort, smtpHost, smtpPort) in `Store.providers`, gespeichert wie `trusted` in UserDefaults (JSON). Strato und WEB.DE sind beim ersten Start vorbelegt und löschbar wie alle anderen. Der WEB.DE-Hinweistext entfällt aus dem Formular und wandert in die README.
- **README komplett auf Englisch** (entschieden) im nightshift-Aufbau (Icon, Badges, Features, Installieren, Updates, Troubleshooting, Entwickeln, Support, Lizenz), plus LICENSE (MIT) und Release-Step bei Tag `v*` wie in nightshift.

## Namensvorschläge

Stil wie `nightshift`/`downmark`: ein kurzes englisches Wort, klein geschrieben, auf Deutsch auch verständlich.

| Name | Idee | Hinweis |
|---|---|---|
| **errand** | direkte Übersetzung von Laufbursche | kurz, frei wirkend |
| **postrun** | Post + Botengang | Kompositum wie nightshift |
| **dispatch** | Versand/Depesche | häufiger Begriff, App-Store-Konflikte möglich |
| **mailrun** | die tägliche Postrunde | eindeutig Mail |
| **inkpost** | Tinte + Post, ruhig | eher literarisch |
| **runner** | Bote, Läufer | sehr generisch |

**Entschieden: dispatch** (Repo `SirOpolov/dispatch`, Bundle-ID `de.siropolov.dispatch`, Anzeigename „Dispatch“).

## Unified Inbox

Das gemeinsame Profil, das die E-Mails aller Profile zeigt, heißt **„Unified Inbox“** (EN) / **„Gemeinsamer Briefkasten“** (DE). Ersetzt überall „Alle Konten“ (Profilwahl, Titel, Toast). Funktion bleibt gleich.

## Dependency Graph

```
Task 1 WEB.DE-Diagnose/Fix  (unabhängig, zuerst: höchstes Risiko)
Task 2 Rebrand + SirOpolov  ── Namensentscheidung
   ├── Task 3 Lokalisierung Grundgerüst + Sprachwahl
   │      ├── Task 4 Views übersetzen
   │      └── Task 5 Store/Models/Fehler übersetzen
   ├── Task 6 Eigene Anbieter (nutzt bereits englische Keys)
   └── Task 7 README + LICENSE + Release (braucht Name, Features final)
```

## Task List

### Phase 1: Fix und Fundament
- [ ] Task 1: WEB.DE verbinden
- [ ] Task 2: Rebrand und Umzug auf SirOpolov

### Checkpoint 1
- [ ] CI grün, App startet unter neuem Namen, WEB.DE-Konto verbindet

### Phase 2: Sprache
- [ ] Task 3: String Catalog und Sprachwahl
- [ ] Task 4: Views auf Englisch/Deutsch
- [ ] Task 5: Toasts, Ordnernamen und Fehler auf Englisch/Deutsch

### Checkpoint 2
- [ ] Gerät auf Englisch: keine deutschen Texte; Wechsel auf Deutsch + Neustart: alles deutsch

### Phase 3: Anbieter und Doku
- [ ] Task 6: Eigene Anbieter anlegen und löschen
- [ ] Task 7: README, LICENSE, Release

### Checkpoint 3
- [ ] Alle Akzeptanzkriterien erfüllt, Tag `v1.0.0` erzeugt ein Release mit IPA

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Neue Bundle-ID löscht lokale Daten und Passwörter | High | Einmalig, im README-Changelog und im Release-Text erwähnen; Konten neu anlegen |
| WEB.DE-Ursache liegt beim Konto (IMAP aus, 2FA), nicht im Code | Med | Fehlermeldung zuerst holen; Hinweise in README/Troubleshooting |
| Sprachwechsel nur nach Neustart | Low | Hinweis direkt unter dem Picker |
| Ohne Mac/Xcode lokal nur CI als Build-Prüfung | Med | Jeder Task einzeln pushen und CI abwarten |
| Bestehendes GitHub-Repo umbenennen | Low | GitHub leitet alte URLs weiter; Remote lokal trotzdem umstellen |

## Open Questions

- Klappt WEB.DE nach Freischalten von IMAP bzw. mit App-Passwort?
- Repo auf GitHub: `gh repo rename dispatch` durch mich (frage vor dem Ausführen) oder durch dich?
