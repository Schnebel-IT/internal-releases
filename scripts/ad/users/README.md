# AD-Benutzerbericht (`list_users.ps1`)

Listet alle Benutzerkonten einer OU oder der ganzen Domäne mit den Angaben, die bei Audits, Offboarding-Kontrollen und Lizenzzählungen gefragt sind: aktiv oder deaktiviert, gesperrt, letzte Anmeldung, Beschäftigungsende, Kennzeichnung als Service-Konto und mehr.

Alle Benutzer werden mit **einer** AD-Abfrage gelesen. Auch große Domänen sind daher in Sekunden fertig.

Bedienung, Fortsetzen nach Abbruch und Ausgabeformat sind für alle AD-Berichte gleich und in der [Übersicht](../README.md) beschrieben.

---

## Start

```powershell
# Assistent
.\list_users.ps1

# Eine OU, zusätzlich getrennte Dateien für aktive und deaktivierte Konten
.\list_users.ps1 -OU "OU=Mitarbeiter,DC=firma,DC=local" -SeparateEnabledDisabled

# Ganze Domäne
.\list_users.ps1 -OutputDir "D:\Reports"
```

Direkt aus GitHub:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; & ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Schnebel-IT/internal-releases/refs/heads/main/scripts/ad/users/list_users.ps1'))) -SeparateEnabledDisabled
```

---

## Parameter

| Parameter | Standard | Beschreibung |
| --- | --- | --- |
| `-OU` | ganze Domäne | Suchbasis als Distinguished Name. Alias: `-SearchBase`, `-OUPath` |
| `-SeparateEnabledDisabled` | aus | Zusätzlich `_Enabled.csv` und `_Disabled.csv` erzeugen. Alias: `-Split` |
| `-DomainName` | eigene Domäne | DNS-Name einer anderen Domäne. Alias: `-Domain` |
| `-Server` | automatisch | Fester Domain Controller |
| `-OutputDir` | `C:\Temp\ADReports` | Zielordner |
| `-OutputFile` | automatisch | Fester Dateipfad, überschreibt `-OutputDir` |
| `-Delimiter` | `;` | CSV-Trennzeichen |
| `-Fresh` | aus | Unterbrochenen Lauf verwerfen und neu beginnen |

---

## Ausgabe

Datei: `ADBenutzer_<Datum>.csv`. Mit `-SeparateEnabledDisabled` kommen `ADBenutzer_<Datum>_Enabled.csv` und `ADBenutzer_<Datum>_Disabled.csv` im gleichen Format hinzu.

| Spalte | Inhalt |
| --- | --- |
| `Anzeigename` | DisplayName |
| `Anmeldename` | sAMAccountName |
| `BenutzernameUPN` | UserPrincipalName |
| `Abteilung` | Department |
| `Position` | Title |
| `Standort` | Office |
| `Status` | `Aktiv` oder `Deaktiviert` |
| `Gesperrt` | `Ja`, wenn das Konto durch Fehlanmeldungen gesperrt ist |
| `Beschaeftigungsende` | Ablaufdatum des Kontos (AccountExpirationDate) |
| `LetzteAnmeldung` | LastLogonDate, auf etwa 14 Tage genau (wird zwischen DCs nur verzögert repliziert) |
| `PasswortGesetzt` | Datum der letzten Passwortänderung |
| `PasswortLaeuftNieAb` | `Ja` / `Nein` |
| `Erstellt` | Erstellungsdatum des Kontos |
| `ServiceKonto` | `Ja`, wenn das Konto als Service- oder Systemkonto erkannt wurde (siehe unten) |
| `Beschreibung` | Description |
| `OU` | Container bzw. OU, in der das Konto liegt |

### Erkennung von Service-Konten

Ein Konto gilt als Service-/Systemkonto, wenn mindestens eines zutrifft:

- Anmeldename beginnt mit `svc_`, `sys_` oder `service_` (auch mit `-` oder `.`)
- Anzeigename enthält „Dienstkonto“ oder „Service“
- Beschreibung enthält „System“, „Dienstkonto“ oder „Service“
- Ein ServicePrincipalName ist gesetzt (typisch für SQL-, IIS- und andere Dienstkonten)
- Eingebautes Konto: Administrator, Gast, krbtgt, DefaultAccount, WDAGUtilityAccount

Die Erkennung ist eine Heuristik. Die Spalte ist als Hinweis gedacht, nicht als verbindliche Einstufung.

---

## Was sich gegenüber Version 1.x geändert hat

- **Fehler behoben:** Version 1.x hat deaktivierte Konten als „Gesperrt“ bezeichnet. `Status` heißt jetzt `Aktiv`/`Deaktiviert`, die echte Sperre steht in der neuen Spalte `Gesperrt`.
- Das Skript nimmt Parameter an (bisher Konfiguration im Skript) und lässt sich dadurch auch als Einzeiler aus GitHub starten.
- Neue Spalten: `Anmeldename`, `Position`, `Gesperrt`, `LetzteAnmeldung`, `PasswortGesetzt`, `PasswortLaeuftNieAb`, `Erstellt`, `Beschreibung`, `OU`.
- Es wird immer eine Gesamtdatei geschrieben. Die getrennten Dateien kommen bei Bedarf hinzu.
- Keine Tabellenausgabe aller Benutzer in der Konsole mehr, nur noch eine Zusammenfassung. Die Daten stehen in der CSV.

---

**Autor:** Luca Baumann · **Version:** 2.0 · **Stand:** 06.10.2026
