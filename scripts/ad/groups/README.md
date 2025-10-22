## 🧾 Active Directory Gruppen-Mitglieder-Analyse

**Datei:** `main/scripts/ad/groups/list_ad_groups.ps1`  
**Version:** 1.1  
**Autor:** Luca Baumann  
**Letzte Änderung:** 22. Oktober 2025

---

## 📄 Übersicht

Das PowerShell-Skript **`list_ad_groups.ps1`** erstellt einen umfassenden Bericht über **Active Directory-Gruppen und Benutzer-Mitgliedschaften**.  
Es kann in **zwei Richtungen** arbeiten:

1. **Gruppenanalyse**  
   → Zeigt **alle Mitglieder zu jeder Gruppe** innerhalb eines OU-Bereichs
2. **Benutzeranalyse**  
   → Zeigt **alle Gruppenmitgliedschaften (direkt & verschachtelt)** zu jedem Benutzer

Beide Modi können über Parameter frei gewählt werden.

---

## ⚙️ Funktionsweise

Das Skript durchsucht Active Directory dynamisch anhand der gewählten Option:

- Im **Gruppenmodus** ermittelt es Gruppen, deren Beschreibung (falls vorhanden) sowie deren Mitglieder.
- Im **Benutzermodus** ermittelt es Benutzerobjekte und listet alle AD-Gruppen, in denen sie Mitglied sind.
- Die Ausgabe kann rekursiv alle verschachtelten Mitgliedschaften auflösen.
- Ergebnisse werden sowohl **in der Konsole** als auch **in einer CSV-Datei** ausgegeben.

---

## 🧩 Parameter

| Parameter     | Typ    | Pflicht | Beschreibung                                                  |
| ------------- | ------ | ------- | ------------------------------------------------------------- |
| `-DomainName` | String | ✅      | AD-Domäne, z. B. `RIETHO.local`                               |
| `-OUPath`     | String | ✅      | LDAP-Suchpfad oder OU, z. B. `OU=Gruppen,DC=RIETHO,DC=local`  |
| `-Mode`       | String | ✅      | "Group" = Gruppenanalyse<br>"User" = Benutzeranalyse          |
| `-Recursive`  | Switch | ❌      | Verschachtelte Mitgliedschaften auflösen                      |
| `-OutputFile` | String | ❌      | Exportpfad für CSV (Standard: `C:\Temp\ADGroups_<Datum>.csv`) |

---

## 🚀 Beispielaufrufe

### 🔹 Gruppenanalyse:

```powershell
.\list_ad_groups.ps1 -DomainName "RIETHO.local" `
 -OUPath "OU=Gruppen,DC=RIETHO,DC=local" `
 -Mode "Group" -Recursive
```

### 🔹 Benutzeranalyse:

```powershell
.\list_ad_groups.ps1 -DomainName "RIETHO.local" `
 -OUPath "OU=Benutzer,DC=RIETHO,DC=local" `
 -Mode "User" -Recursive
```

---

## 📊 Beispielausgabe (Konsole)

```text
═══════════════════════════════════════════════════════════════════

AD-Gruppenanalyse – Start: 21.10.2025 13:00

Autor: Luca Baumann

───────────────────────────────────────────────────────────────────

Domäne: HOME.local

OU-Pfad:OU=Gruppen,DC=HOME,DC=local

Rekursive Auflösung: Aktiv

Export-Datei:   C:\Temp\ADGroups_20251021_1300.csv

═══════════════════════════════════════════════════════════════════

Gruppen gefunden: 42

Mitglieder gesamt: 385

GroupNameMemberName   MemberType


---
g-Vertrieb   HOME\m.musterfrau   User

g-Vertrieb   HOME\g-MarketingGroup

g-IT HOME\admin.svc  User

Export abgeschlossen.

═══════════════════════════════════════════════════════════════════
```

---

## 📁 CSV-Output

Die exportierte Datei enthält standardmäßig folgende Spalten:

| GroupName  | MemberName        | MemberType | Domain     |
| ---------- | ----------------- | ---------- | ---------- |
| g-Vertrieb | HOME\m.musterfrau | User       | HOME.local |
| g-IT       | HOME\g-Support    | Group      | HOME.local |

---

## 🧠 Voraussetzungen

- Windows PowerShell 5.1 oder neuer
- RSAT-Tools / Active Directory-Modul (`Import-Module ActiveDirectory`)
- Leserechte für die angegebene OU und deren Gruppen
- Schreibrechte auf dem Zielpfad des CSV-Exports

---

## ⚡ Tipp: Rekursive Auflösung

Wenn du mit Gruppennestings arbeitest (z. B. wenn `g-IT` wiederum `g-Admins` enthält),
nutze den Schalter `-Recursive`, um auch diese Mitglieder rekursiv aufzulösen:

```powershell
.\list_ad_groups.ps1 -DomainName "HOME.local" -OUPath "OU=Gruppen,DC=HOME,DC=local" -Recursive
```

---

## 🧰 Fehlerbehandlung

- Gruppen, auf die kein Zugriff besteht, werden übersprungen.

- Netzwerkfehler oder Anmeldeprobleme werden protokolliert.

- Bei Bedarf kann -Verbose für detaillierte Laufzeitinformationen verwendet werden.

---

## 🧩 Beispielhafte CSV-Verarbeitung in PowerShell

```powershell
$csv = Import-Csv "C:\\Temp\\ADGroups_20251021_1300.csv"
$csv | Group-Object GroupName | Select-Object Name, Count
```

Damit erhältst du z. B. eine Übersicht, wie viele Mitglieder jede Gruppe hat.

---

## 🪪 Metadaten

| Feld                  | Wert                                      |
| --------------------- | ----------------------------------------- |
| Autor                 | Luca Baumann                              |
| Version               | 1.0                                       |
| Letzte Aktualisierung | 21. Oktober 2025                          |
| Repository            | Schnebel-IT / internal-releases           |
| Pfad                  | main/scripts/ad/groups/list_ad_groups.ps1 |

---

## 🪄 Lizenzierung

Dieses Skript ist Teil des internen Toolsets Schnebel-IT internal releases

und darf ausschließlich intern oder mit Zustimmung von Schnebel IT verwendet werden.

---

© 2025 Luca Baumann / Schnebel IT

Internal Automation & Infrastructure Tools

---
