# foxdock-history

Das Plugin `history` für FoxDock, das Plugin-System für die IDE von Visual FoxPro 9. Bewahrt die vorherige Version jedes Formulars, jeder Klassenbibliothek, jedes Berichts, Etiketts und Menüs auf, das Sie bearbeiten, mit Diff und Wiederherstellen.

> Auch auf Englisch ([README.md](README.md)) und Spanisch ([README_ES.md](README_ES.md)).

## Installieren

Sie brauchen FoxDock und [FoxPack](https://irwinrodriguez.dev/products/foxpack).

- In FoxDock: **FoxDock > Plugins > Plugin-Center...**, **Verfügbar**, `history` auswählen und **Installieren** drücken.
- Von der Konsole: `foxpack plugin add history`.

Wenn `history` mit Ihrem FoxDock-Installer kam, zeigt das Plugin-Center seine neuen Versionen unter **Aktualisierungen**.

## Das Plugin `history`

Jedes Mal, wenn Sie ein Formular, eine Klasse, einen Bericht, ein Etikett oder ein Menü bearbeiten,
bewahrt FoxDock auf, wie es vorher war. Wenn die Änderung schiefgeht, holen Sie mit einem Knopf eine
frühere Fassung zurück.

**Was es aufbewahrt.** Die Binärdateien mit Memo: `.scx`, `.vcx`, `.frx`, `.lbx` und `.mnx`, **immer mit
ihrem Memo** (`.sct`, `.vct`, `.frt`, `.lbt`, `.mnt`). Es bewahrt nie das eine ohne das andere auf. Wenn
FoxKit installiert ist, bewahrt es auch den Text von FoxBin2Prg auf (`.SC2`, `.VC2`...). Mit ihm sehen
Sie, was sich geändert hat. Die `.pjx` nicht, weil sie sich ständig ändert. Der Text entsteht im
Hintergrund, ohne dass Sie warten müssen: Die Fassung ist vom ersten Moment an da, und solange sagt ihr
Text `being made`. Ein großes Formular kann eine Minute brauchen; fordern Sie den Vergleich vorher an,
wartet **Unterschiede** (Diff) darauf.

**Wo.** In `%LOCALAPPDATA%\FoxDock\history\`, ein Ordner pro Ordner Ihrer Quellen und darin einer pro
Datei und einer pro Fassung, benannt nach Datum und Uhrzeit:

```
history\c-proyectos-ventas-forms\clientes.scx\20261029-194004\
    clientes.scx   clientes.sct   clientes.SC2   version.txt
```

`version.txt` sagt, von welcher Datei die Fassung ist, wann und warum sie entstand, und was mit dem Text
geschah. **FoxDock > Verlauf > Verlaufsordner öffnen** (FoxDock > History > Open history folder) öffnet den Ordner.

**Wann.**

- **Wenn Sie die Datei aus dem Projekt-Manager öffnen**, entsteht die Fassung, bevor sich der Designer
  öffnet.
- **Wenn sich ein Projekt öffnet**, kopiert FoxDock die Binärdateien des Projekts, die noch keine
  identische Fassung haben (gleiche Größe, gleiches Datum, gleiche Uhrzeit): ein paar auf einmal, ohne
  dass Sie es merken, und ohne Text, der erst entsteht, wenn Sie einen Vergleich anfordern. Das ist der
  **Ausgangsstand** (baseline), und wenn er fertig ist, sagt das Protokoll, wie viele es kopiert hat und
  wie viele schon da waren. Bei einem großen Projekt dauert das erste Mal einige Minuten; danach prüft es
  nur noch und braucht Sekunden. Eine Datei, die in diesem Moment in Gebrauch ist (in einem Designer, oder
  eine Klassenbibliothek eines Formulars, das in seinem offen ist), wird übersprungen und beim nächsten
  Öffnen des Projekts erneut versucht.
- **Wenn Sie `MODIFY FORM` im Befehlsfenster eingeben**, öffnet der Designer die Datei und sperrt sie,
  bevor FoxDock davon weiß, und sie lässt sich nicht mehr kopieren. Die vorherige Fassung ist dann die
  aufbewahrte, die mit der Datei identisch ist (gleiche Größe, gleiches Datum, gleiche Uhrzeit), auch
  eine alte, zu der Sie sie mit **Wiederherstellen** (Restore) zurückgeholt haben. Für eine Datei in einem offenen Projekt
  hat der Ausgangsstand sie schon. Wenn es keine gibt
  (eine lose Datei außerhalb eines Projekts, die nie durch FoxDock ging), ist der vorherige Zustand
  verloren, und das Protokoll meldet es.
- **Wenn sich der Designer schließt.** Wenn Sie nichts geändert haben, wird die beim Öffnen entstandene
  Fassung verworfen: Öffnen und Schließen füllt den Verlauf nicht. Wenn Sie etwas geändert haben, wird
  auch der jetzige Zustand aufbewahrt, und so ist die neueste Fassung immer das, was auf der Festplatte
  steht.

Es bewahrt 20 Fassungen pro Datei auf. Darüber hinaus wird die älteste gelöscht.

**Wie Sie wiederherstellen.** **FoxDock > Verlauf > Verlauf der aktuellen Datei...** (FoxDock > History > History of the current file...) zeigt die Fassungen
der Datei im Designer im Vordergrund, oder die der Datei, die Sie aus der Liste wählen.

- **Unterschiede** öffnet in einem Editor die Zeilen, die sich zwischen dieser Fassung und der Datei in ihrem
  jetzigen Zustand geändert haben.
- **Wiederherstellen** kopiert diese Fassung, Binärdatei und Memo, über die Datei. Vorher bewahrt es den Zustand,
  den es gleich überschreibt, als weitere Fassung auf. So lässt sich eine Wiederherstellung auf dem
  gleichen Weg rückgängig machen: Sie stellen diese Fassung wieder her.

Es fragt nicht nach einer Bestätigung: Der Knopf ist die Bestätigung. Der Hinweis oben rechts in VFP und das Protokoll
sagen, was es getan hat.

**Was es nicht tut.**

- **Es stellt nicht wieder her, solange der Designer offen ist.** Schließen Sie ihn vorher. Sonst meldet
  es das und rührt nichts an.
- **Ohne FoxKit gibt es keinen Vergleich.** Die Fassungen werden trotzdem aufbewahrt (Binärdatei und
  Memo), und in `version.txt` steht `text: none (FoxKit not installed)`.
- **Es verfolgt keine Dateien, die es nicht findet.** Ein `MODIFY FORM` auf eine Datei, die weder in
  einem offenen Projekt noch im `SET PATH` liegt, lässt sich aus dem Fenstertitel nicht finden, und das
  Protokoll meldet es.

**Die Optionen** (`config.json`, `"options": { "history": { ... } }`): `extensions` (die Liste der
Erweiterungen, standardmäßig `"scx,vcx,frx,lbx,mnx"`), `maxVersions` (20), `baseline` (`true`: der
Ausgangsstand beim Öffnen eines Projekts) und `settleSeconds` (3: wenn ein Designer schließt und die Datei
unverändert aussieht, wie lange history noch hinschaut, bevor es die Bearbeitung als unverändert ansieht, für
Gespeichertes, das spät auf die Platte kommt).

Für den Agenten gibt es drei Tools, `ide_history_list`, `ide_history_diff` und `ide_history_restore`:
AGENT-TOOLS_DE.md § 5.

## Über dieses Handbuch

Dieser Text ist der Abschnitt über `history` aus dem Plugin-Handbuch von FoxDock. Die Verweise auf andere Abschnitte (§) und auf AGENT-TOOLS zeigen auf die Dokumente, die FoxDock in seinem Ordner `docs` installiert.

## Lizenz

MIT. Siehe [LICENSE](LICENSE).
