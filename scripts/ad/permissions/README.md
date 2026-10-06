# NTFS-Berechtigungsbericht (`list_permissions.ps1`)

Liest die NTFS-Berechtigungen eines Ordners und seiner Unterordner bis zu einer festgelegten Tiefe und schreibt jede Berechtigung als eigene Zeile in eine CSV-Datei. Typische Einsätze sind Fileserver-Audits, Migrationen und die Frage, wer eigentlich worauf Zugriff hat.

Bedienung, Fortsetzen nach Abbruch und Ausgabeformat sind für alle AD-Berichte gleich und in der [Übersicht](../README.md) beschrieben.

---

## Start

```powershell
# Assistent
.\list_permissions.ps1

# Drei Ebenen (Startordner plus zwei darunter), nur Konten der Domäne FIRMA
.\list_permissions.ps1 -Path "D:\Daten" -MaxDepth 3 -Domain "FIRMA"

# Ganze Freigabe, nur explizit gesetzte Rechte (keine vererbten)
.\list_permissions.ps1 -Path "\\fs01\Daten" -MaxDepth 0 -ExcludeInherited
```

Direkt aus GitHub:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; & ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Schnebel-IT/internal-releases/refs/heads/main/scripts/ad/permissions/list_permissions.ps1'))) -Path 'D:\Daten' -MaxDepth 3 -Domain 'FIRMA'
```

---

## Parameter

| Parameter | Standard | Beschreibung |
| --- | --- | --- |
| `-Path` | (Pflicht, Assistent fragt nach) | Startordner, lokal oder UNC. Alias: `-StartPath` |
| `-MaxDepth` | `3` | Tiefe **inklusive** Startordner: `1` = nur Startordner, `3` = Startordner plus zwei Ebenen, `0` = unbegrenzt |
| `-Domain` | alle Konten | Nur Konten dieser Domäne ausgeben (NetBIOS-Name, z. B. `FIRMA`) |
| `-ExcludeInherited` | aus | Nur explizit gesetzte Berechtigungen ausgeben, vererbte weglassen |
| `-OutputDir` | `C:\Temp\ADReports` | Zielordner |
| `-OutputFile` | automatisch | Fester Dateipfad, überschreibt `-OutputDir` |
| `-Delimiter` | `;` | CSV-Trennzeichen |
| `-Fresh` | aus | Unterbrochenen Lauf verwerfen und neu beginnen |

> **Tipp:** `-ExcludeInherited` macht den Bericht oft um ein Vielfaches kleiner. Er zeigt dann nur die Stellen, an denen jemand Rechte bewusst gesetzt hat.

---

## Ausgabe

Datei: `NTFSBerechtigungen_<Datum>.csv`

| Path | Depth | Account | AccessControlType | FileSystemRights | AppliesTo | IsInherited | Owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D:\Daten | 1 | BUILTIN\Administratoren | Allow | FullControl | Dieser Ordner, Unterordner und Dateien | False | BUILTIN\Administratoren |
| D:\Daten\Vertrieb | 2 | FIRMA\g-Vertrieb | Allow | Modify, Synchronize | Dieser Ordner, Unterordner und Dateien | False | BUILTIN\Administratoren |
| D:\Daten\Vertrieb | 2 | FIRMA\m.muster | Allow | ReadAndExecute, Synchronize | Nur Unterordner und Dateien | True | BUILTIN\Administratoren |

| Spalte | Inhalt |
| --- | --- |
| `Path` | Ordnerpfad |
| `Depth` | Ebene, Startordner = 1 |
| `Account` | Benutzer oder Gruppe. Konten, die nicht mehr existieren, erscheinen als SID (`S-1-5-21-...`). |
| `AccessControlType` | `Allow` oder `Deny` |
| `FileSystemRights` | Rechte im Klartext. Generische Rechte werden übersetzt, z. B. `268435456` → `FullControl`. |
| `AppliesTo` | Gültigkeitsbereich wie in der Windows-Sicherheitsansicht, z. B. „Nur Unterordner und Dateien“ |
| `IsInherited` | `True`, wenn die Berechtigung vom übergeordneten Ordner geerbt ist |
| `Owner` | Besitzer des Ordners |

---

## Verhalten im Detail

- **Ordner ohne Zugriff** werden übersprungen und mit Grund im Fehler-Log festgehalten. Der Lauf bricht dabei nicht ab.
- **Junctions und symbolische Links** werden nicht verfolgt. Das verhindert Endlosschleifen und doppelte Zählung. Die Anzahl steht in der Zusammenfassung.
- **Lange Pfade** über 260 Zeichen werden auch unter Windows PowerShell 5.1 gelesen.
- **Netzwerkfehler** (Freigabe kurz nicht erreichbar) lassen den betroffenen Ordner offen. Ein erneuter Aufruf mit denselben Parametern liest nur diese Ordner nach.
- Für vollständige Ergebnisse das Skript als Administrator ausführen.

---

## Was sich gegenüber Version 1.x geändert hat

- **Fehler behoben:** Version 1.x hat die übergebenen Parameter ignoriert und die Werte aus dem Skript verwendet, auch beim Einzeiler aus GitHub. Der Startordner selbst fehlte im Bericht.
- Die Ordnersuche stoppt an der gewünschten Tiefe. Version 1.x hat erst den kompletten Baum eingelesen und danach gefiltert, was bei großen Fileservern Stunden dauern konnte.
- Berechtigungen werden direkt über .NET gelesen statt mit `Get-Acl`. Das ist deutlich schneller.
- Neue Spalten: `Depth`, `AppliesTo`, `Owner`. Die bisherigen Spalten heißen unverändert.
- Neuer Parameter `-ExcludeInherited`. `-MaxDepth 0` bedeutet „unbegrenzt“.
- CSV mit `;` statt `,`. Wer das alte Format braucht, setzt `-Delimiter ','`.

---

**Autor:** Luca Baumann · **Version:** 2.0 · **Stand:** 06.10.2026
