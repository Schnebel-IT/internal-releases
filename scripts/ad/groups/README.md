# AD-Gruppenbericht (`list_ad_groups.ps1`)

Erstellt einen Bericht über Gruppenmitgliedschaften in Active Directory, wahlweise in zwei Richtungen:

| Modus | Frage | Eine Zeile pro |
| --- | --- | --- |
| `Group` | Wer ist in welcher Gruppe? | Gruppe und Mitglied |
| `User` | In welchen Gruppen ist ein Benutzer? | Benutzer und Gruppe |

Mit `-Recursive` werden verschachtelte Gruppen bis in jede Tiefe aufgelöst. Die Spalte `Membership` zeigt, auf welchem Weg die Mitgliedschaft besteht.

Bedienung, Fortsetzen nach Abbruch und Ausgabeformat sind für alle AD-Berichte gleich und in der [Übersicht](../README.md) beschrieben.

---

## Start

```powershell
# Assistent
.\list_ad_groups.ps1

# Alle Gruppen einer OU mit allen (auch verschachtelten) Mitgliedern
.\list_ad_groups.ps1 -Mode Group -OUPath "OU=Gruppen,DC=firma,DC=local" -Recursive

# Alle Benutzer einer OU mit ihren direkten Gruppen
.\list_ad_groups.ps1 -Mode User -OUPath "OU=Benutzer,DC=firma,DC=local"
```

Direkt aus GitHub:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; & ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Schnebel-IT/internal-releases/refs/heads/main/scripts/ad/groups/list_ad_groups.ps1'))) -Mode Group -Recursive
```

---

## Parameter

| Parameter | Standard | Beschreibung |
| --- | --- | --- |
| `-Mode` | `Group` | `Group` = Gruppe → Mitglieder, `User` = Benutzer → Gruppen |
| `-OUPath` | ganze Domäne | Suchbasis als Distinguished Name. Alias: `-SearchBase`, `-OU` |
| `-Recursive` | aus | Verschachtelte Gruppen vollständig auflösen |
| `-DomainName` | eigene Domäne | DNS-Name einer anderen Domäne. Alias: `-Domain` |
| `-Server` | automatisch | Fester Domain Controller |
| `-OutputDir` | `C:\Temp\ADReports` | Zielordner |
| `-OutputFile` | automatisch | Fester Dateipfad, überschreibt `-OutputDir` |
| `-Delimiter` | `;` | CSV-Trennzeichen |
| `-Fresh` | aus | Unterbrochenen Lauf verwerfen und neu beginnen |

---

## Ausgabe

Datei: `ADGruppen_<Datum>.csv` (Modus `Group`) bzw. `ADBenutzerGruppen_<Datum>.csv` (Modus `User`)

### Modus `Group`

| GroupName | Description | MemberName | MemberDisplayName | MemberType | MemberEnabled | Membership | Domain |
| --- | --- | --- | --- | --- | --- | --- | --- |
| g-Vertrieb | Vertrieb Innendienst | m.muster | Max Muster | user | True | Direct | firma.local |
| g-Vertrieb | Vertrieb Innendienst | g-Marketing | | group | | Direct | firma.local |
| g-Vertrieb | Vertrieb Innendienst | e.beispiel | Eva Beispiel | user | True | Nested | firma.local |

### Modus `User`

| UserName | DisplayName | UserEnabled | GroupName | GroupDescription | Membership | Domain |
| --- | --- | --- | --- | --- | --- | --- |
| m.muster | Max Muster | True | Domain Users | | Primary | firma.local |
| m.muster | Max Muster | True | g-Vertrieb | Vertrieb Innendienst | Direct | firma.local |
| m.muster | Max Muster | True | g-Alle | Alle Mitarbeiter | Nested | firma.local |

### Spalte `Membership`

| Wert | Bedeutung |
| --- | --- |
| `Direct` | direkt eingetragenes Mitglied |
| `Nested` | Mitglied über eine verschachtelte Gruppe (nur mit `-Recursive`) |
| `Primary` | Mitgliedschaft über die primäre Gruppe, z. B. *Domain Users* |

`MemberType` ist die AD-Objektklasse: `user`, `group`, `computer`, `contact`, `foreignSecurityPrincipal` (Konto aus einer vertrauten Domäne, wird als `DOMÄNE\Name` aufgelöst) usw.

---

## Was sich gegenüber Version 1.x geändert hat

- **Fehler behoben:** Version 1.x hat keine Zeilen exportiert (die Ergebnisse gingen in einer Funktion verloren). `-Recursive` hat nur eine Ebene aufgelöst.
- Kein `Get-ADGroupMember` mehr. Dadurch gibt es kein Limit bei 5.000 Mitgliedern und keine Abbrüche durch Mitglieder aus fremden Domänen.
- Mitglieder der primären Gruppe (z. B. *Domain Users*) werden mit ausgegeben.
- Neue Spalten: `MemberDisplayName`, `MemberEnabled`, `Membership` (Modus `Group`) sowie `DisplayName`, `UserEnabled`, `Membership` (Modus `User`). Die bisherigen Spalten heißen unverändert.
- `-DomainName` und `-OUPath` sind optional.
- CSV mit `;` statt `,`. Wer das alte Format braucht, setzt `-Delimiter ','`.

---

## Hinweise

- Benutzer mit einer **eigenen** primären Gruppe (nicht *Domain Users*, *Domain Computers* usw.) erscheinen im Modus `Group` nicht als `Primary`-Mitglied dieser Gruppe. Im Modus `User` sind sie korrekt enthalten.
- Im Modus `Group` werden Mitglieder aus der eigenen Domäne und Fremdkonten aus vertrauten Domänen gefunden. Mitglieder aus **anderen Domänen desselben Forests** (Universal-Gruppen) fehlen.

---

**Autor:** Luca Baumann · **Version:** 2.0 · **Stand:** 06.10.2026
