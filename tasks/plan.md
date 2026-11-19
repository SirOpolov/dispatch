# Implementation Plan: Mails verschieben und automatisch löschen

## Overview

Mails lassen sich bisher nur nach Spam, Papierkorb oder zurück in den Posteingang verschieben. Neu: in jeden Serverordner verschieben, einzeln und gesammelt. Dazu pro Ordner eine selbst gewählte Dauer in Tagen, nach der Mails beim Abruf automatisch gelöscht werden.

## Ist-Stand

- `Destination` (`Models.swift`) kennt nur `.inbox`, `.spam`, `.trash`. `Store.move` setzt daraus den Zielordner und ruft `IMAP.move` (UID MOVE, Fallback COPY + EXPUNGE). Das ist alles wiederverwendbar.
- `MessageView.actions` zeigt „Mark as Spam“, „Not Spam“ und „Restore“ über `moveButton`.
- `MessageList` hat ein Kontextmenü (Absender-Regeln) und im Auswahlmodus eine Leiste unten (gelesen, Favorit, löschen).
- `Store.download` läuft pro Konto und Ordner, beim Abruf im Vordergrund und im Hintergrund. Dort steckt schon die Automatik, die Mails von Spam-Absendern verschiebt. Die Lösch-Automatik kommt an dieselbe Stelle.
- `Account` wird als JSON gespeichert. Neue optionale Felder sind abwärtskompatibel.

## Architecture Decisions

- **`Destination.folder(String)`** statt einer eigenen Verschiebe-Funktion. `Store.move` bekommt nur einen Fall mehr.
- **Ordnerliste zum Verschieben:** `account.syncedFolders` ohne den aktuellen Ordner, mit den Namen aus `account.title(.folder(name))`.
- **Mehrere Mails verschieben** nur, wenn alle gewählten Mails zum selben Konto gehören (Ordner sind pro Konto). In der Unified Inbox mit gemischter Auswahl ist der Knopf deaktiviert.
- **Lösch-Dauer** als `retention: [String: Int]?` im `Account` (Ordnername → Tage). 0 oder kein Eintrag heißt aus.
- **Einstellung im ⋯-Menü der Ordneransicht:** Eintrag „Auto-Delete…“ öffnet ein kleines Formular mit Stepper und Zahlenfeld (1 bis 3650 Tage) und einem Schalter an/aus. Unread/Read/All gehören zum Ordner INBOX. Favorites, Verified und Unified Inbox haben keine eigene Regel.
- **Löschen beim Abruf** in `Store.download`: Mails, die älter als X Tage sind, wandern in den Papierkorb. Im Papierkorb selbst, oder wenn das Konto keinen hat, wird endgültig gelöscht. **Favoriten bleiben immer erhalten** (entschieden).
- **Alter = Datum aus dem Mail-Header** (`mail.date`). Fehlt es oder ist es kaputt, wird es beim Einlesen auf den Abrufzeitpunkt gesetzt (`.now`), dadurch wird die Mail frühestens X Tage später gelöscht.
- **Testbare Auswahl** über eine freie Funktion `expired(_ mails:, days:, now:) -> [Mail]`, mit Unit-Test.

## Dependency Graph

```
Destination.folder + Store.move
   ├── Task 1 Einzeln verschieben (MessageView, Kontextmenü)
   └── Task 2 Gesammelt verschieben (Auswahlleiste)
Account.retention
   ├── Task 3 Einstellung pro Ordner (UI)
   └── Task 4 Löschen beim Abruf (Store.download + Test)
Task 5 README + Release (nach 1 bis 4)
```

## Task List

### Phase 1: Verschieben
- [ ] Task 1: Einzelne Mail in beliebigen Ordner verschieben
- [ ] Task 2: Mehrere Mails verschieben

### Checkpoint 1
- [ ] CI grün, Verschieben am Gerät geprüft (Mail taucht im Zielordner auf, auch im Webmail)

### Phase 2: Automatisch löschen
- [ ] Task 3: Lösch-Dauer pro Ordner einstellen
- [ ] Task 4: Abgelaufene Mails beim Abruf löschen

### Checkpoint 2
- [ ] CI grün, Regel mit 1 Tag an einem Testordner geprüft, Favoriten bleiben

### Phase 3: Doku
- [ ] Task 5: README und Release v1.1.0

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Automatik löscht ungewollt viele Mails (falsche Tageszahl, Posteingang) | High | Standard aus, Zielordner ist der Papierkorb statt endgültig, Favoriten ausgenommen, Toast und Protokolleintrag mit Anzahl |
| Falsches Datum im Header (Spam mit altem Datum) | Med | Betrifft nur Ordner mit aktiver Regel, Ziel ist der Papierkorb |
| Ordnernamen mit Sonderzeichen (UTF-7) | Low | Es wird der rohe Servername genutzt, wie bei Spam/Papierkorb schon heute |
| Auswahl über mehrere Konten | Low | Knopf deaktiviert, wenn die Auswahl gemischt ist |

## Open Questions

- Keine. Favoriten sind ausgenommen (entschieden), die Dauer wird frei in Tagen eingegeben.
