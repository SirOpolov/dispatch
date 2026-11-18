# Todo

Build/Test laufen nur in CI (GitHub Actions, macos-26): `xcodegen generate && xcodebuild test -scheme Dispatch -destination 'platform=iOS Simulator,name=iPhone 17'`.

## Task 1: WEB.DE verbinden

**Description:** Herausfinden, woran der WEB.DE-Login scheitert, und die Ursache beheben. Code-seitig wahrscheinlichster Kandidat: `EHLO laufbursche` ist kein FQDN. Außerdem verhindert ein SMTP-Fehler das Speichern des ganzen Kontos, ohne zu sagen, ob IMAP oder SMTP schuld war.

**Acceptance criteria:**
- [ ] Konto-Seite geprüft: WEB.DE-Webmail → Einstellungen → POP3/IMAP → Zugriff erlauben; bei 2-Faktor App-Passwort verwenden
- [ ] Fehlermeldung im Formular nennt, ob IMAP oder SMTP gescheitert ist (Präfix „IMAP:“ / „SMTP:“)
- [ ] SMTP grüßt mit `EHLO [127.0.0.1]`
- [ ] WEB.DE-Konto (IMAP 993, SMTP 587) verbindet, empfängt und sendet

**Verification:**
- [ ] CI grün
- [ ] Manuell: WEB.DE-Konto anlegen, Mail an sich selbst senden und empfangen

**Dependencies:** None. Bekannte Meldung: „NO authentication …“ = IMAP-LOGIN abgelehnt

**Files likely touched:** `Laufbursche/Store.swift`, `Laufbursche/SMTP.swift`

**Estimated scope:** S

## Task 2: Rebrand und Umzug auf SirOpolov

**Description:** Neuer App-Name überall, Bundle-ID `de.siropolov.dispatch`, BG-Task-ID, Keychain-Service, Ordner, Target, Scheme, Workflow, Git-Remote auf `github.com/SirOpolov/dispatch`.

**Acceptance criteria:**
- [ ] `grep -ri "greismicha\|laufbursche"` findet nichts mehr (außer Git-Historie)
- [ ] `project.yml`, Ordner `Dispatch/` und `DispatchTests/`, Workflow-Scheme und IPA-Name passen zusammen
- [ ] `git remote -v` zeigt `SirOpolov/dispatch`
- [ ] Lokaler Ordner `~/Development/laufbursche` → `~/Development/dispatch` (letzter Schritt, nach dem Commit, außerhalb der laufenden Session)

**Verification:**
- [ ] CI grün, Artefakt heißt `Dispatch.ipa`
- [ ] Manuell: App zeigt neuen Namen auf dem Homescreen, Hintergrundabruf registriert sich

**Dependencies:** None (Name: dispatch)

**Files likely touched:** `project.yml`, `.github/workflows/build.yml`, `Store.swift`, `Models.swift` (Keychain-Service), `SMTP.swift` (MIME-Boundary), Ordner-Umbenennung

**Estimated scope:** M

## Checkpoint 1
- [ ] CI grün
- [ ] App startet unter neuem Namen, WEB.DE verbindet
- [ ] Review mit dir

## Task 3: String Catalog und Sprachwahl

**Description:** `Localizable.xcstrings` anlegen (Quellsprache `en`, Übersetzung `de`), `developmentLanguage: en` in `project.yml`. In den Einstellungen ein Picker System/English/Deutsch, der `AppleLanguages` setzt, mit Hinweis „Gilt nach Neustart“. Settings-Screen und AccountForm als erster vertikaler Schnitt komplett umstellen.

**Acceptance criteria:**
- [ ] Gerät ohne Auswahl auf Englisch: Einstellungen und Kontoformular englisch
- [ ] Auswahl Deutsch + Neustart: beide Screens deutsch
- [ ] Auswahl bleibt nach Neustart erhalten

**Verification:**
- [ ] CI grün
- [ ] Manuell: Sprachwechsel hin und zurück

**Dependencies:** Task 2

**Files likely touched:** `project.yml`, `Dispatch/Localizable.xcstrings`, `SettingsView.swift`, `AccountForm.swift`

**Estimated scope:** M

## Task 4: Views auf Englisch/Deutsch

**Description:** Restliche SwiftUI-Texte auf englische Keys mit deutscher Übersetzung umstellen.

**Acceptance criteria:**
- [ ] Mailbox, Nachricht, Verfassen, App-Rahmen ohne deutsche Literale im Code
- [ ] Profil „Alle Konten“ heißt „Unified Inbox“ / „Gemeinsamer Briefkasten“ (Profilwahl, Kopfzeile)
- [ ] Alle Keys im Catalog mit deutscher Übersetzung

**Verification:**
- [ ] CI grün
- [ ] Manuell: jeden Screen in beiden Sprachen öffnen

**Dependencies:** Task 3

**Files likely touched:** `MailboxView.swift`, `MessageView.swift`, `ComposeView.swift`, `DispatchApp.swift`, `Localizable.xcstrings`

**Estimated scope:** M

## Task 5: Toasts, Ordnernamen und Fehler auf Englisch/Deutsch

**Description:** Strings außerhalb von Views über `String(localized:)`: Store-Toasts und Log, `mailCount` (Plural im Catalog), `Account.title(_:)`, Fehlertexte in IMAP/SMTP/MIME/Connection, Mitteilungen.

**Acceptance criteria:**
- [ ] Toasts und Mitteilungen in gewählter Sprache, inkl. Singular/Plural
- [ ] Toast beim Wechsel ins gemeinsame Profil: „Unified Inbox“ / „Gemeinsamer Briefkasten“
- [ ] Bestehende Tests angepasst und grün

**Verification:**
- [ ] CI grün (MailTests)
- [ ] Manuell: Mails löschen/markieren, Toast in beiden Sprachen

**Dependencies:** Task 3

**Files likely touched:** `Store.swift`, `Models.swift`, `IMAP.swift`, `SMTP.swift`, `MIME.swift`, `Connection.swift`, `DispatchTests/MailTests.swift`

**Estimated scope:** M

## Checkpoint 2
- [ ] Englisches Gerät: keine deutschen Texte
- [ ] Deutsch gewählt: alles deutsch
- [ ] Review mit dir

## Task 6: Eigene Anbieter anlegen und löschen

**Description:** `Provider` (name, imapHost, imapPort, smtpHost, smtpPort) als Liste in `Store`, in UserDefaults als JSON. Strato und WEB.DE beim ersten Start vorbelegt. Einstellungen: Abschnitt „Providers“ mit Hinzufügen-Formular und Wischen-zum-Löschen. Kontoformular listet die gespeicherten Anbieter statt der festen Buttons und bietet „Save as provider“ für die eingetragenen Server.

**Acceptance criteria:**
- [ ] Anbieter anlegen, er erscheint im Kontoformular und füllt die Felder
- [ ] Anbieter löschen (auch Strato/WEB.DE), er bleibt nach Neustart weg
- [ ] Bestehende Konten bleiben unverändert, wenn ihr Anbieter gelöscht wird

**Verification:**
- [ ] CI grün, ein Test für Speichern/Laden der Anbieterliste
- [ ] Manuell: anlegen, nutzen, löschen, Neustart

**Dependencies:** Task 3 (Texte direkt englisch/deutsch)

**Files likely touched:** `Models.swift`, `Store.swift`, `SettingsView.swift`, `AccountForm.swift`, `Localizable.xcstrings`

**Estimated scope:** M

## Task 7: README, LICENSE, Release

**Description:** README komplett auf Englisch im nightshift-Aufbau: Icon, Badges (Download, CI, iOS 26, MIT, PayPal), Kurzbeschreibung, Features, Installieren (Sideloadly/iloader), Updates, Troubleshooting inkl. WEB.DE-IMAP-Freischaltung und App-Passwort, Entwickeln, Support, Lizenz. MIT-`LICENSE`. Workflow: Tags `v*`, `permissions: contents: write`, Release-Step mit `gh release create`.

**Acceptance criteria:**
- [ ] README rendert auf GitHub mit funktionierenden Badges und Links auf SirOpolov
- [ ] Feature-Liste deckt Unified Inbox, Sprachen, eigene Anbieter ab
- [ ] Tag `v1.0.0` erzeugt ein Release mit IPA

**Verification:**
- [ ] Manuell: README auf GitHub ansehen, Release-Seite prüfen

**Dependencies:** Task 2, Task 6

**Files likely touched:** `README.md`, `LICENSE`, `.github/workflows/build.yml`

**Estimated scope:** S

## Checkpoint 3
- [ ] Alle Akzeptanzkriterien erfüllt
- [ ] Release `v1.0.0` vorhanden
- [ ] Review mit dir
