# 🧾 NTFS-Berechtigungs-Analyse (list_permissions.ps1)

## 📄 Übersicht

Das PowerShell-Skript **`list_permissions.ps1`** erstellt einen detaillierten Bericht über NTFS-Berechtigungen für Ordner innerhalb eines definierten Pfads.  
Es bietet zusätzlich:

- Limitation der Analyse auf eine **maximale Ordner-Tiefe**
- Automatisches **Überspringen von Ordnern ohne Zugriffsrechte**
- Optionalen **Domänenfilter** (z. B. nur `HOME\`-Konten)
- **CSV-Export** der Ergebnisse für Auswertungen oder Audits

---

## ⚙️ Funktionsweise

Das Skript durchsucht rekursiv alle Unterordner des angegebenen Startpfads – aber nur bis zur konfigurierten Tiefe.  
Für jeden erreichbaren Ordner wird die **Access Control List (ACL)** abgefragt und gefiltert.

> 🔒 Ordner, für die der aktuelle Benutzer keine Berechtigung besitzt, werden automatisch übersprungen.  
> 📁 Nur Benutzer und Gruppen aus der angegebenen Domäne (wenn gesetzt) werden aufgelistet.

---

## 🧩 Parameter

| Parameter     | Typ    | Pflicht | Beschreibung                                                              |
| ------------- | ------ | ------- | ------------------------------------------------------------------------- |
| `-Path`       | String | ✅      | Startordner, z. B. `D:\Daten`                                             |
| `-MaxDepth`   | Int    | ❌      | Maximale Ordnertiefe, Standard: `3`                                       |
| `-Domain`     | String | ❌      | Nur Benutzer und Gruppen aus dieser Domäne berücksichtigen (z. B. `HOME`) |
| `-OutputFile` | String | ❌      | Pfad zur CSV-Datei; Standard: `C:\Temp\FileserverPermissions_<Datum>.csv` |

---

## 🚀 Beispielaufruf (Einzeiler)

Der folgende Befehl lädt das Skript **direkt aus GitHub (RAW-Link)** herunter und führt es mit deinen Parametern aus:

```powershell
iex "& { $(Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Schnebel-IT/internal-releases/refs/heads/main/scripts/ad/permissions/list_permissions.ps1') } -Path 'D:\Daten' -MaxDepth 3 -Domain 'HOME'"
```

💡 Du kannst natürlich jeden Parameter anpassen – z. B. andere Tiefe, Pfad oder Domäne.

---

## 📊 Beispielausgabe (Konsole)

```text
═══════════════════════════════════════════════════════════════════
 NTFS-Berechtigungs-Analyse – Start: 21.10.2025 13:00
 Autor: Luca Baumann
───────────────────────────────────────────────────────────────────
 Startpfad:          D:\Daten
 Maximale Tiefe:     3 Ebenen
 Domänenfilter:      HOME
 Export-Datei:       C:\Temp\FileserverPermissions_20251021_1300.csv
═══════════════════════════════════════════════════════════════════

Berechtigungen gefunden: 215 Einträge.

Path                                  Account              AccessControlType  FileSystemRights  IsInherited
----                                  --------             -----------------  ----------------  ------------
D:\Daten\Personalverwaltung           HOME\g-CAD         Allow              Modify, Read      True
D:\Daten\Projekte\ProjektA            HOME\m.mustermann  Allow              FullControl       False
...
Export abgeschlossen.
Skript erfolgreich beendet.
═══════════════════════════════════════════════════════════════════
```

---

## 📁 CSV-Ausgabe

Die Exportdatei enthält Spalten wie:

| Path                        | Account           | AccessControlType | FileSystemRights | IsInherited |
| --------------------------- | ----------------- | ----------------- | ---------------- | ----------- |
| D:\Daten\Personalverwaltung | HOME\g-CAD        | Allow             | Modify, Read     | True        |
| D:\Daten\Projekte\ProjektA  | HOME\m.mustermann | Allow             | FullControl      | False       |

---

## 📌 Hinweise

- Das Skript benötigt **PowerShell 5.1 oder neuer**
- Stelle sicher, dass dein Benutzerkonto **Leserechte** auf die Ordnerstruktur besitzt
- Verwende **administrative Berechtigungen**, um vollständige Ergebnisse zu erhalten
- Die CSV-Datei kann in Excel oder Power BI weiterverarbeitet werden

---

**Author:** Luca Baumann  
**Version:** 1.2  
**Last updated:** 21. Oktober 2025  
**Repository:** [Schnebel-IT / internal-releases](https://github.com/Schnebel-IT/internal-releases)

---
