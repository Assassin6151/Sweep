# Sweep – Feature-Liste

Diese Liste ist die Planungsgrundlage für Sweep. Sie ist aus einer Analyse des Funktionsumfangs
gängiger Mac-Cleaner (u. a. des Open-Source-Projekts MacSai) entstanden, wurde aber eigenständig
formuliert, priorisiert und auf die Wünsche für Sweep zugeschnitten. Code, Texte und Gestaltung
sind komplett eigene Arbeit.

Bewusst **nicht** enthalten: CPU-/RAM-/Performance-Überwachung, Menüleisten-Monitor,
„Optimizer“, die nur Systemauslastung anzeigen, sowie Wartungsskripte.

## Übersicht / Smart Scan
- Ein Klick prüft Junk, große Dateien und Duplikate parallel
- Fortschritt je Bereich, Ergebnisse als große, klare Zahlen
- Direkt weiter in das jeweilige Modul oder Junk sofort (mit Vorschau) entfernen
- Speicherbelegung des Startvolumes als Balken (belegt / verfügbar / „gefunden“)

## Junk-Cleaner
- Kategorien: Benutzer-Caches, App-Container-Caches, System-Caches, Benutzer- und System-Logs,
  Absturzberichte, temporäre Dateien (älter als 3 Tage), Xcode (DerivedData, Archive,
  Gerätesupport, Simulator-Caches), Homebrew-Downloads und -Logs, weitere Entwickler-Caches
  (npm, Yarn, pip, CocoaPods, Gradle), Papierkorb
- Jede Kategorie mit Erklärung und Risikohinweis; riskantere Kategorien sind standardmäßig abgewählt
- Auswahl je Kategorie und je Eintrag

## App-Deinstallation
- Findet Apps in `/Applications`, `~/Applications` und Hersteller-Unterordnern
- Findet zugehörige Dateien in ~17 Library-Bereichen (Benutzer und System) über Bundle-ID
  und – vorsichtiger – über den App-Namen (Treffer per Name sind standardmäßig abgewählt)
- **Komplett deinstallieren** (App + Reste) oder **Zurücksetzen** (nur Einstellungen/Caches/Daten)
- Erkennt **lange ungenutzte Apps** (letzte Nutzung laut Spotlight, Schwelle einstellbar)
- Schützt Apple-Apps und Sweep selbst, warnt bei laufenden Apps und bietet Beenden an

## Speicherkarte (Visualisierung)
- Beliebigen Ordner oder Volume analysieren
- Eigene Squarified-Treemap mit Drill-down, Breadcrumb-Navigation und Hover-Infos
- Parallele Balkenliste der größten Einträge
- Im Finder zeigen / in den Papierkorb legen (mit Vorschau)

## Duplikate
- Mehrstufige Erkennung: Dateigröße → Teil-Hash → vollständiger SHA-256
- Harte Links (gleiche Datei) werden nicht als Duplikat gewertet
- Automatische Auswahl: neuestes / ältestes / kürzester Pfad behalten
- Garantie: Aus jeder Gruppe bleibt immer mindestens eine Datei erhalten

## Große & alte Dateien
- Mindestgröße und „nicht benutzt seit“ einstellbar
- Filter nach Art (Video, Archiv, Disk-Image, Installer, Sonstiges), Sortierung nach Größe / Datum

## Adware-Check
- Prüft Launch Agents und Launch Daemons (Benutzer und System), Anmeldeobjekte und
  Browser-Erweiterungen (Safari, Chrome-basierte Browser, Firefox)
- Eigene Liste bekannter Adware-Familien plus Heuristiken (versteckte Pfade, unsignierte
  Programme, Skripte, die Code nachladen, fehlende Programme, erzwungene Erweiterungen)
- Einträge können als vertrauenswürdig markiert werden
- Klarer Hinweis: **kein vollwertiger Virenscanner**

## Aktivitätsprotokoll
- Jede Aktion mit Zeitpunkt, Modul, Pfaden und Größe
- Wiederherstellen aus dem Papierkorb, solange die Datei dort noch liegt

## Sicherheit
- Löschen = in den Papierkorb (einzige Ausnahme: „Papierkorb leeren“ mit eigener Warnung)
- Blocklist geschützter Pfade (System, Benutzer-Hauptordner, Schlüsselbund, iCloud Drive …),
  zusätzlich eigene Ausschlüsse in den Einstellungen
- Vorschau mit Pfad und Größe vor jeder Löschung, explizite Bestätigung
- Alles wird protokolliert
- Onboarding erklärt Festplattenvollzugriff und führt in die Systemeinstellungen
