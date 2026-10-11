# Sweep

Sweep ist ein nativer Mac-Cleaner für macOS 14 und neuer, geschrieben in Swift und SwiftUI.
Er findet Junk-Dateien, deinstalliert Apps restlos, zeigt, wo der Speicherplatz bleibt, spürt
Duplikate sowie große und alte Dateien auf und prüft typische Verstecke von Adware.

Sweep löscht nie etwas, ohne zu fragen, und legt standardmäßig alles in den Papierkorb.

## Funktionen

| Modul | Was es macht |
|---|---|
| **Smart Scan** | Prüft Junk, große Dateien und Duplikate parallel und zeigt, wie viel Platz frei werden kann |
| **Junk-Cleaner** | App- und System-Caches, Caches in App-Containern, Protokolle, Absturzberichte, temporäre Dateien, Xcode (DerivedData, Gerätesupport, Simulator, Archive), Homebrew, npm/Yarn/pip/CocoaPods/Gradle/SwiftPM, Papierkorb |
| **Deinstallieren** | Findet zu jeder App die zugehörigen Dateien in rund 20 Library-Bereichen, deinstalliert oder setzt zurück und erkennt lange ungenutzte Apps |
| **Speicherkarte** | Treemap und Balkenliste eines beliebigen Ordners, mit Drill-down |
| **Duplikate** | Vergleicht Inhalte (Größe → Teil-Hash → SHA-256), behält von jeder Gruppe immer mindestens eine Kopie |
| **Große & alte Dateien** | Filter nach Größe, „nicht benutzt seit“ und Dateiart |
| **Adware-Check** | Launch Agents/Daemons, Anmeldeobjekte, Browser-Erweiterungen (Safari, Chromium-Familie, Firefox), erzwungene Browser-Richtlinien, versteckte Programme. **Kein vollwertiger Virenscanner**, das sagt die App auch deutlich |
| **Aktivitätsprotokoll** | Was wann entfernt wurde, mit Wiederherstellen aus dem Papierkorb |

Bewusst nicht enthalten: CPU-, RAM- oder Performance-Überwachung.

Die vollständige Feature-Liste steht in [FEATURES.md](FEATURES.md).

## Sicherheit

- **Papierkorb statt Löschen.** Alles wird mit `FileManager.trashItem` verschoben. Nur „Papierkorb leeren“
  löscht endgültig, und das nur für Dateien, die bereits im Papierkorb liegen. Dafür gibt es eine
  zusätzliche Bestätigung.
- **Sperrliste.** `ProtectedPaths` blockiert Systemordner (`/System`, `/usr`, `/bin`, …), die Hauptordner
  des Benutzerkontos, Schlüsselbund, iCloud Drive, Mail, Nachrichten, `~/.ssh`, Dateien innerhalb von
  App-Paketen und Fotos-Mediatheken, Apple-Apps und Sweep selbst. Pfad-Tricks wie `..` und
  symbolisch verlinkte Elternordner werden aufgelöst. In den Einstellungen kannst du eigene Ordner schützen.
- **Vorschau.** Vor jeder Löschung zeigt Sweep jeden Pfad mit Größe; geschützte Einträge sind markiert
  und werden übersprungen.
- **Protokoll.** Jede Aktion landet als JSON in `~/Library/Application Support/Sweep/activity-log.json`.
- **Kein Netzwerk.** Sweep sendet keine Daten und enthält keine Analyse- oder Telemetriefunktionen.

## Voraussetzungen

- macOS 14 Sonoma oder neuer
- Xcode 15 oder neuer (entwickelt und getestet mit Xcode 27)
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), nur nötig,
  wenn du `project.yml` änderst

## Bauen

### In Xcode

1. `Sweep.xcodeproj` öffnen
2. Schema **Sweep** und als Ziel **My Mac** wählen
3. **Run** (⌘R)

Die App ist ad hoc signiert („Sign to Run Locally“), ein Apple-Entwicklerkonto ist nicht nötig.
Wenn du sie weitergeben willst, trage unter *Signing & Capabilities* dein Team ein.

### Im Terminal

```bash
# Falls xcode-select noch auf die Command Line Tools zeigt:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Release-Build
xcodebuild -project Sweep.xcodeproj -scheme Sweep -configuration Release \
  -derivedDataPath build/DerivedData build

open build/DerivedData/Build/Products/Release/Sweep.app
```

### Tests

```bash
xcodebuild -project Sweep.xcodeproj -scheme Sweep -derivedDataPath build/DerivedData test
```

Die Unit-Tests prüfen die Scan- und Sicherheitslogik (Sperrliste, Löschen, Protokoll, Junk-Scan,
Reste-Suche, Treemap-Layout, Verzeichnisbaum, Duplikate, große Dateien, Adware-Heuristiken, Smart Scan).
Sie arbeiten ausschließlich in temporären Ordnern und mit einem Test-Papierkorb. Dein echter
Papierkorb und deine Dateien bleiben unberührt.

### Projektdatei neu erzeugen

Das Xcode-Projekt wird aus `project.yml` generiert und ist eingecheckt. Nach Änderungen an der
Ordnerstruktur oder den Build-Einstellungen:

```bash
xcodegen generate
```

### App-Icon neu zeichnen

```bash
swift scripts/make-icon.swift Sweep/Resources/Assets.xcassets/AppIcon.appiconset
```

## Festplattenvollzugriff

macOS schützt viele Ordner (Mail, Safari, Nachrichten, die Container anderer Apps, den Papierkorb).
Ohne Freigabe überspringt Sweep diese Bereiche bewusst, damit kein Scan an einer Systemabfrage
hängen bleibt, und markiert sie als „nicht lesbar“. So erteilst du die Freigabe:

1. *Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff*
2. Sweep einschalten (oder mit „+“ hinzufügen)
3. Sweep neu starten

Die App erklärt das beim ersten Start und unter *Berechtigungen* und öffnet die passende Stelle
in den Systemeinstellungen.

> **Hinweis für Entwickler:** Ad-hoc-signierte Builds bekommen bei jedem Neubau eine neue Signatur.
> macOS kann eine erteilte Freigabe dann nicht mehr zuordnen. Entferne den alten Eintrag in der Liste
> und füge den neuen Build hinzu, oder signiere mit einem festen Entwicklerzertifikat.

Für den optionalen Check der Anmeldeobjekte fragt macOS einmal, ob Sweep „System Events“ steuern darf.

## Architektur

```
Sweep/
├── App/                 Einstieg, AppModel (hält die ViewModels), Sidebar, Navigation
├── Core/
│   ├── Activity/        Aktivitätsprotokoll (persistiert als JSON)
│   ├── FileSystem/      Größenmessung, FileWalker, Fortschritts-Drosselung
│   ├── Models/          Module, Pfade, Dateiarten, Formatierung
│   ├── Permissions/     Festplattenvollzugriff, datenschutzgeschützte Orte
│   ├── Safety/          Sperrliste, SafeDeleter, DeletionService
│   └── System/          Codesignatur, launchctl, Shell-Helfer
├── Modules/             Ein Ordner pro Modul mit View, ViewModel und Service
│   ├── SmartScan/
│   ├── JunkCleaner/
│   ├── Uninstaller/
│   ├── SpaceMap/
│   ├── Duplicates/
│   ├── LargeFiles/
│   ├── Malware/
│   ├── ActivityLog/
│   ├── Permissions/  Onboarding/  Settings/
├── Shared/Components/   Wiederverwendbare UI (Karten, große Zahlen, Vorschau-Sheet, …)
└── Resources/           Info.plist, Entitlements, Assets
SweepTests/              Unit-Tests
```

- **Services** sind `Sendable`-Structs ohne UI-Abhängigkeiten. Sie bekommen ihre Pfade über
  `SystemPaths` injiziert und sind dadurch gegen temporäre Test-Ordner testbar.
- **ViewModels** sind `@Observable` und `@MainActor`. Sie starten die Services in Hintergrund-Tasks
  (Swift Concurrency) und reichen den Fortschritt gedrosselt an die UI weiter. Die Oberfläche blockiert nie.
- **Alle Löschungen** laufen über `DeletionService` → `SafeDeleter` → `ProtectedPaths` und werden
  protokolliert. Kein Modul ruft `FileManager.removeItem` direkt auf.
- Scans sind abbrechbar. „Abbrechen“ kehrt sofort zurück, die Hintergrundarbeit endet am nächsten Prüfpunkt.

## Tastenkürzel

| Kürzel | Aktion |
|---|---|
| ⌘1 … ⌘9 | Module in der Sidebar |
| ⌘R | Scan im aktuellen Modul starten |
| ⌘K | Auswahl aufräumen / entfernen |
| ⇧⌘S | Smart Scan starten |
| ⌘↑ | In der Speicherkarte eine Ebene nach oben |
| ⌘, | Einstellungen (eigene geschützte Ordner) |

## Inspiration

Der Funktionsumfang orientiert sich an gängigen Mac-Cleanern, unter anderem am Open-Source-Projekt
[MacSai](https://github.com/iliyami/MacSai). Code, Texte, Gestaltung, Icon und Name von Sweep
sind eigenständig entstanden.
