# dispatch

Schlanker Mail-Client für iOS 26 (SwiftUI, Liquid Glass), ohne Fremdbibliotheken.

- Ein Profil pro E-Mail-Adresse, Wechsel oben in der Seitenleiste
- Empfang per IMAP, Versand per SMTP (Port 993/465 = SSL/TLS, sonst STARTTLS)
- Posteingang mit Ungelesen / Gelesen / Alle, dazu Favoriten, Spam, Papierkorb und alle weiteren Serverordner
- Mehrfachauswahl, "Alle löschen" (Favoriten bleiben), "Alle als gelesen markieren", Suche
- Antworten, Allen antworten, Weiterleiten, Anhänge senden und öffnen, Kopie in "Gesendet"
- Automatischer Abruf bei geöffneter App, im Hintergrund durch iOS mit Mitteilungen
- E-Mails werden als Text angezeigt, HTML und Bilder erst nach Umschalten
- Profil „Alle Konten“ mit gemeinsamem Ordner und kontoübergreifender Suche
- Vertrauenswürdige Absender (Gruppe „Verifiziert“, HTML direkt an) und Spam-Absender (automatisch in Spam), per Gedrückthalten oder in den Einstellungen
- Absender-Icons direkt von der Absender-Domain, sonst Buchstaben-Platzhalter; eigene Icons für vertrauenswürdige Absender
- Akzentfarbe frei wählbar
- Passwörter im Schlüsselbund (AutoFill aus Passwortmanagern), E-Mails pro Konto getrennt

## Server

| Anbieter | IMAP | SMTP |
|---|---|---|
| Strato | imap.strato.de:993 | smtp.strato.de:465 |
| WEB.DE | imap.web.de:993 | smtp.web.de:587 |

Bei WEB.DE muss IMAP im Webmail unter Einstellungen → POP3/IMAP freigeschaltet sein.

## Build

GitHub Actions erzeugt das Projekt mit XcodeGen, führt die Tests aus und baut eine unsignierte `Dispatch.ipa`. Installation wie bei Nightshift.
