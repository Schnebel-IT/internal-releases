# 🚀 M365 Benutzer- & Lizenzreport

Hallo und herzlich willkommen! 👋

Dieses Projekt enthält ein PowerShell-Skript, das dir hilft, einen schnellen Überblick über deine Microsoft 365 Benutzer zu bekommen. Es listet dir auf, welche Gruppen sie zugewiesen haben und welche Lizenzen sie nutzen.

---

### 🚨 ACHTUNG:

Das Skript ist derzeit noch nicht fertig und enthält daher noch viele Bugs!

---

### 🚨 Wichtig: Das benötigte Modul installieren!

Damit das Skript funktioniert, benötigst du das **Microsoft Graph PowerShell SDK**. Keine Sorge, die Installation ist super einfach!

Öffne eine **PowerShell als Administrator** (Rechtsklick auf PowerShell -> "Als Administrator ausführen") und gib folgenden Befehl ein:

```powershell
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
```

Bestätige die Nachfragen mit `J` (Ja) oder `A` (Alle). Das Modul wird dann heruntergeladen und installiert.

---

### 📝 Was macht das Skript?

Das PowerShell-Skript (`Get-M365UserReport.ps1`) erledigt folgende Aufgaben für dich:

1.  **Verbindet sich mit Microsoft 365:** Es öffnet ein Anmeldefenster, in dem du dich mit einem Administratorkonto (oder einem Konto mit den nötigen Berechtigungen) anmelden kannst.
2.  **Sammelt Benutzerdaten:** Es holt sich alle Benutzer aus deinem M365-Tenant.
3.  **Findet Gruppen:** Für jeden Benutzer ermittelt es die direkten Gruppenmitgliedschaften.
4.  **Listet Lizenzen auf:** Es zeigt dir die zugewiesenen Lizenzen und deren Service-Pläne an.
5.  **Exportiert eine CSV:** Alle gesammelten Infos werden in einer übersichtlichen CSV-Datei gespeichert. Der Dateiname enthält automatisch Datum und Uhrzeit, damit deine älteren Reports nicht überschrieben werden.

---

### 🚀 So nutzt du das Skript:

1.  **Modul installieren:** Stell sicher, dass du das [Microsoft Graph PowerShell SDK](#-wichtig-das-benötigte-modul-installieren) installiert hast.
2.  **Skript herunterladen:** Lade die Datei `Get-M365UserReport.ps1` aus diesem Repository herunter.
3.  **Skript ausführen:** Öffne eine **normale PowerShell** (nicht unbedingt als Administrator, es sei denn, du hast das Modul für "AllUsers" installiert) und navigiere zu dem Ordner, in den du das Skript gespeichert hast.
    Führe es dann so aus:
    ```powershell
    .\Get-M365UserReport.ps1
    ```
4.  **Anmelden:** Es öffnet sich ein Anmeldefenster für Microsoft 365. Melde dich mit einem Konto an, das die Berechtigungen zum Lesen von Benutzern, Gruppen und Lizenzen hat (meist ein globaler Admin oder ein User-Admin).
5.  **Fertig!** Die CSV-Datei wird im selben Ordner erstellt, in dem das Skript liegt.

---

### 💡 Wichtige Hinweise:

*   **Berechtigungen:** Das Konto, mit dem du dich anmeldest, muss mindestens `User.Read.All`, `Group.Read.All` und `Directory.Read.All` Berechtigungen haben.
*   **Dauer:** Je nach Anzahl deiner M365-Benutzer kann das Skript etwas Zeit in Anspruch nehmen. Hab Geduld!
*   **Lizenzen:** Die Lizenzen werden über die Service-Plan-IDs aufgelistet. Wenn du die exakten Lizenznamen (wie "Microsoft 365 Business Standard") möchtest, müsstest du diese IDs eventuell manuell zuordnen oder das Skript entsprechend erweitern.

---

### 🤝 Fragen oder Feedback?

Wenn du Fragen zum Skript hast, einen Fehler findest oder Verbesserungsvorschläge hast, melde dich gerne!

---

**Dein Team von Schnebel-IT**
