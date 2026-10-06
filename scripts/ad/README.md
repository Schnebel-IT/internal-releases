# AD-Berichte

Drei PowerShell-Skripte für Bestandsaufnahmen in Active Directory und auf Fileservern. Alle drei sehen gleich aus, bedienen sich gleich und schreiben ihre Ergebnisse als CSV-Datei.

| Skript | Bericht |
| --- | --- |
| [`groups/list_ad_groups.ps1`](groups/README.md) | Gruppen und ihre Mitglieder oder Benutzer und ihre Gruppen, auf Wunsch mit verschachtelten Gruppen |
| [`users/list_users.ps1`](users/README.md) | Benutzerkonten mit Status, Sperre, letzter Anmeldung, Beschäftigungsende und Service-Konto-Kennzeichnung |
| [`permissions/list_permissions.ps1`](permissions/README.md) | NTFS-Berechtigungen von Ordnern bis zu einer festgelegten Tiefe |

---

## Schnellstart

### Startmenü (alle drei Berichte)

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; & ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Schnebel-IT/internal-releases/refs/heads/main/scripts/ad/ad_tools.ps1')))
```

Das Menü fragt, welcher Bericht erstellt werden soll, und startet dann den Assistenten des Skripts.

### Ein Skript direkt aus GitHub starten

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; & ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Schnebel-IT/internal-releases/refs/heads/main/scripts/ad/groups/list_ad_groups.ps1'))) -Mode Group -Recursive
```

Den Dateinamen am Ende der URL tauschen und die Parameter anhängen. Ohne Parameter startet der Assistent.

> Der erste Teil (`SecurityProtocol ... 3072`) aktiviert TLS 1.2. Ohne ihn schlägt der Download auf Windows Server 2012 R2 und 2016 fehl.

### Aus einem lokalen Checkout

```powershell
.\scripts\ad\ad_tools.ps1                     # Menü
.\scripts\ad\users\list_users.ps1             # Assistent
.\scripts\ad\users\list_users.ps1 -OU "OU=Mitarbeiter,DC=firma,DC=local"
```

---

## Gemeinsame Eigenschaften

### Assistent oder Parameter

- **Ohne Parameter** fragt ein kurzer Assistent alle Optionen ab. Jede Frage hat einen sinnvollen Standardwert, Enter übernimmt ihn. Am Ende zeigt der Assistent den passenden Befehl für die Wiederholung ohne Assistent.
- **Mit Parameter** läuft das Skript ohne Rückfragen durch. Das eignet sich für geplante Tasks und Remoting.

### Fortsetzen nach Abbruch

Bricht ein Lauf ab, durch Strg+C, einen Verbindungsabbruch oder einen Neustart, genügt es, **denselben Befehl erneut auszuführen**. Das Skript findet den unterbrochenen Lauf anhand der Parameter, setzt an der richtigen Stelle fort und schreibt in dieselbe CSV-Datei weiter. Die Datei enthält danach weder doppelte noch fehlende Zeilen.

| Situation | Verhalten |
| --- | --- |
| Gleicher Befehl nach Abbruch | wird automatisch fortgesetzt |
| Andere Parameter | neuer Lauf, der alte bleibt liegen |
| `-Fresh` | unterbrochenen Lauf verwerfen und neu beginnen |
| Elemente mit Verbindungsfehlern | bleiben offen; ein erneuter Aufruf holt nur diese nach |
| Elemente ohne Zugriff (z. B. Zugriff verweigert) | werden übersprungen und im Fehler-Log notiert |

Den Fortschritt hält eine Datei `<bericht>.csv.progress` neben der CSV fest. Nach einem vollständigen Lauf wird sie automatisch gelöscht.

### Ausgabe

- Ordner: `C:\Temp\ADReports` (Parameter `-OutputDir`). Fehlt der Ordner, wird er angelegt.
- CSV: UTF-8 mit BOM und Trennzeichen `;`, damit Excel Umlaute und Spalten ohne Importassistent richtig anzeigt. Das Trennzeichen lässt sich mit `-Delimiter ','` ändern.
- `<bericht>_Fehler.log`: übersprungene Elemente mit Grund. Die Datei existiert nur, wenn es Meldungen gab.
- Konsole: Fortschrittsbalken mit Restzeit und alle 30 Sekunden eine Statuszeile, auch in Transkripten und geplanten Tasks.

### Läuft auf jedem Server

- Windows PowerShell 5.1 und PowerShell 7
- Windows Server 2012 R2 bis 2025, Server Core, ISE, Remoting (`Enter-PSSession`) und geplante Tasks
- Reine ASCII-Ausgabe ohne Sonderzeichen oder Farbcodes, daher keine kaputten Zeichen bei falscher Codepage
- Jedes Skript ist eigenständig, eine einzelne Datei reicht

### Geschwindigkeit und Zuverlässigkeit

- Alle AD-Abfragen gehen an **einen** Domain Controller, der beim Start ermittelt wird. Das ist schneller und liefert konsistente Daten, auch beim Fortsetzen.
- Kurzzeitige Verbindungsfehler (DC nicht erreichbar, ADWS-Timeout) werden bis zu dreimal mit Wartezeit wiederholt.
- Verschachtelte Gruppen werden über die AD-Abfrage `LDAP_MATCHING_RULE_IN_CHAIN` oder im Speicher aufgelöst, nicht Ebene für Ebene.
- Die Ordnersuche stoppt an der gewünschten Tiefe, statt erst den ganzen Baum einzulesen.

---

## Voraussetzungen

| Skript | Benötigt |
| --- | --- |
| Gruppen, Benutzer | PowerShell-Modul **ActiveDirectory** (RSAT) und Leserechte im AD |
| Berechtigungen | Leserechte auf die Ordner, am besten als Administrator oder mit Sicherungsrechten ausführen |

RSAT installieren:

```powershell
Install-WindowsFeature RSAT-AD-PowerShell                                   # Windows Server
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0   # Windows 10/11
```

---

## Fehlersuche

| Meldung | Ursache und Lösung |
| --- | --- |
| `Das PowerShell-Modul "ActiveDirectory" fehlt` | RSAT installieren (siehe oben) |
| `Suchbasis nicht gefunden` | Den Distinguished Name der OU prüfen, z. B. mit `Get-ADOrganizationalUnit -Filter *` |
| Download schlägt fehl | TLS-1.2-Teil des Einzeilers mitkopieren und Proxy oder Firewall prüfen |
| `Lauf wurde nicht abgeschlossen` | Denselben Befehl erneut ausführen, das Skript setzt fort |

---

**Autor:** Luca Baumann · **Version:** 2.0 · **Stand:** 06.10.2026 · **Repository:** [Schnebel-IT / internal-releases](https://github.com/Schnebel-IT/internal-releases)
