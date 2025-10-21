    ## 🧾 Active Directory Gruppen-Mitglieder-Analyse

    **Datei:** `main/scripts/ad/groups/list_ad_groups.ps1`
    **Version:** 1.0
    **Autor:** Luca Baumann
    **Letzte Änderung:** 21. Oktober 2025

    ---

    ## 📄 Übersicht

    Das PowerShell-Skript **`list_ad_groups.ps1`** erstellt einen strukturierten Bericht darüber, **welche Benutzer und Gruppen in bestimmten Active Directory-Gruppen Mitglied sind**.
    Es ist besonders hilfreich für:

    - Sicherheits-Audits (z. B. Compliance-Kontrollen)
    - Übersicht von Gruppenstrukturen innerhalb einer OU
    - Vorbereitung von Migrations- oder Bereinigungsvorgängen
    - Export und Analyse von Mitgliedschaften in Excel, Power BI o. Ä.

    ---

    ## ⚙️ Funktionsweise

    1. Das Skript verbindet sich mit der angegebenen **Active Directory Domäne**.
    2. Es durchsucht die definierte **OU (Organizational Unit)** nach Gruppenobjekten.
    3. Für jede gefundene Gruppe werden alle Mitglieder (Benutzer, Computer, Gruppen) aufgelistet.
    4. Optional kann eine **rekursive Auflösung** aktiviert werden, bei der auch Mitglieder verschachtelter Gruppen aufgelistet werden.
    5. Die Ergebnisse werden **in der Konsole** angezeigt und **als CSV-Datei exportiert**.

    ---

    ## 🧩 Parameter

    | Parameter | Typ | Pflicht | Beschreibung |
    |------------|------|----------|---------------|
    | `-DomainName` | String | ✅ | AD-Domäne, z. B. `RIETHO.local` |
    | `-OUPath` | String | ✅ | LDAP-Suchpfad der Gruppen (z. B. `OU=Gruppen,DC=RIETHO,DC=local`) |
    | `-Recursive` | Switch | ❌ | Verschachtelte Gruppen auflösen |
    | `-OutputFile` | String | ❌ | Exportpfad für CSV-Datei (Standard: `C:\Temp\ADGroups_<Datum>.csv`) |

    ---

    ## 🚀 Beispielaufruf

    ### Direktaufruf über Repository (GitHub RAW)
    ```powershell
    iex "& { $(Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Schnebel-IT/internal-releases/refs/heads/main/scripts/ad/groups/list_ad_groups.ps1') } -DomainName 'RIETHO.local' -OUPath 'OU=Gruppen,DC=RIETHO,DC=local' -Recursive"
    ```

    ### Lokale Ausführung
    ```powershell
    .\list_ad_groups.ps1 -DomainName "RIETHO.local" -OUPath "OU=Gruppen,DC=RIETHO,DC=local" -Recursive
    ```

    ---

    ## 📊 Beispielausgabe (Konsole)

```text
═══════════════════════════════════════════════════════════════════

AD-Gruppenanalyse – Start: 21.10.2025 13:00

Autor: Luca Baumann

───────────────────────────────────────────────────────────────────

Domäne:             RIETHO.local

OU-Pfad:            OU=Gruppen,DC=RIETHO,DC=local

Rekursive Auflösung: Aktiv

Export-Datei:       C:\Temp\ADGroups_20251021_1300.csv

═══════════════════════════════════════════════════════════════════

Gruppen gefunden: 42

Mitglieder gesamt: 385

GroupName                MemberName               MemberType


---
g-Vertrieb               RIETHO\m.musterfrau       User

g-Vertrieb               RIETHO\g-Marketing        Group

g-IT                     RIETHO\admin.svc          User

Export abgeschlossen.

═══════════════════════════════════════════════════════════════════
```

    ---

    ## 📁 CSV-Output

    Die exportierte Datei enthält standardmäßig folgende Spalten:

    | GroupName | MemberName | MemberType | Domain |
    |------------|-------------|-------------|---------|
    | g-Vertrieb | RIETHO\m.musterfrau | User | RIETHO.local |
    | g-IT | RIETHO\g-Support | Group | RIETHO.local |

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
    .\list_ad_groups.ps1 -DomainName "RIETHO.local" -OUPath "OU=Gruppen,DC=RIETHO,DC=local" -Recursive
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

    | Feld | Wert |
    |------|------|
    | Autor | Luca Baumann |
    | Version | 1.0 |
    | Letzte Aktualisierung | 21. Oktober 2025 |
    | Repository | Schnebel-IT / internal-releases |
    | Pfad | main/scripts/ad/groups/list_ad_groups.ps1 |

---

    ## 🪄 Lizenzierung

Dieses Skript ist Teil des internen Toolsets Schnebel-IT internal releases

und darf ausschließlich intern oder mit Zustimmung von Schnebel IT verwendet werden.

---

© 2025 Luca Baumann / Schnebel IT

Internal Automation & Infrastructure Tools

---
