# laufbursche

Schlanker Mail-Client für iOS 26 (SwiftUI, Liquid Glass), ohne Fremdbibliotheken.

- Ein Profil pro E-Mail-Adresse, Wechsel oben in der Seitenleiste
- Empfang per IMAP, Versand per SMTP (Port 993/465 = SSL/TLS, sonst STARTTLS)
- Posteingang mit Ungelesen / Gelesen / Alle, dazu Spam und Papierkorb
- Automatischer Abruf, solange die App offen ist (Intervall in den Einstellungen)
- E-Mails werden als Text angezeigt, HTML und Bilder erst nach Umschalten
- Passwörter im Schlüsselbund, E-Mails pro Konto getrennt zwischengespeichert

## Server

| Anbieter | IMAP | SMTP |
|---|---|---|
| Strato | imap.strato.de:993 | smtp.strato.de:465 |
| WEB.DE | imap.web.de:993 | smtp.web.de:587 |

Bei WEB.DE muss IMAP im Webmail unter Einstellungen → POP3/IMAP freigeschaltet sein.

## Build

GitHub Actions erzeugt das Projekt mit XcodeGen, führt die Tests aus und baut eine unsignierte `Laufbursche.ipa`. Installation wie bei Nightshift.
