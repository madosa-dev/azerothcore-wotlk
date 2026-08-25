# Companion-Pets anpassen

Wie du Icon, Name, Tooltip, Modell und Größe der sechs mod-madosa-Pets selbst
änderst — Lootbot, Craftbot, Questbot, Bankbot, Auctionbot, Classtrainer.

Alles läuft über eine Datei:

```
modules/mod-madosa/tools/clientpatch/build_patches.py
```

Ganz oben steht ein Block `PETS`. Wert ändern, Skript laufen lassen, fertig.

```fish
cd modules/mod-madosa/tools/clientpatch
python3 build_patches.py             # baut nach out/, ändert nichts
python3 build_patches.py --install   # baut und installiert
mysql -h127.0.0.1 -uacore -p acore_world < out/pet_ascension_models.sql
```

Danach **worldserver neu starten** und den Client starten. Reihenfolge ist egal,
aber der Client muss beim `--install` **geschlossen** sein — das Skript bricht
sonst von selbst ab, siehe Fallstricke.

---

## Was wo herkommt

Das ist der Teil, der am meisten Zeit kostet, wenn man ihn nicht weiß: Ein Pet
hat **drei völlig getrennte Darstellungs-Ketten**. Wer nur eine anfasst, wundert
sich, warum sich die Hälfte nicht ändert.

| Was du siehst | Kette | Stellschraube in `PETS` |
|---|---|---|
| Modell in der Welt | `creature_template_model.CreatureDisplayID` → `CreatureDisplayInfo.dbc` → `CreatureModelData.dbc` → `.m2` | `model`, `texture`, `dbc_scale`, `display_scale` |
| Icon des Items in der Tasche | `item_template.displayid` → `ItemDisplayInfo.dbc` Feld 5 | `icon` |
| Icon + Tooltip im Begleiter-Tab und auf der Aktionsleiste | `Spell.dbc` Feld 133/136/170 → `SpellIcon.dbc` | `icon`, `spell_name`, `spell_desc` |

Der Begleiter-Tab zieht sein Icon über `GetCompanionInfo` aus dem **Zauber**,
nicht aus dem Item. Deshalb braucht es beide Einträge, obwohl es dasselbe Bild ist.

---

## Ein neues Icon

1. Namen suchen (ohne `.blp`, ohne Pfad):

   ```fish
   cd modules/mod-madosa/tools/clientpatch
   python3 -c "
   import sys; sys.path.insert(0,'.')
   from mpq import MPQ
   m = MPQ('$HOME/Games/ascension-wow2/drive_c/Program Files/Ascension Launcher/resources/ascension-live/Data/patch-I.MPQ')
   for n in m.read_file('(listfile)').decode('ascii','replace').split():
       if 'robot' in n.lower(): print(n)
   "
   ```

   Ascension hat rund 70.000 Icons, die dein Client nicht kennt. Suchbegriffe, die
   sich gelohnt haben: `mechagon`, `engineering_90`, `guildperk`, `toolbox`,
   `custom_`, `70_professions`.

2. In `PETS` bei `icon=` eintragen, ohne Pfad und ohne Endung.
3. Bauen und installieren.

Vorher anschauen kannst du dir jedes Icon so:

```fish
python3 -c "
import sys, io; sys.path.insert(0,'.')
from mpq import MPQ
from PIL import Image
m = MPQ('<pfad>/patch-I.MPQ')
d = m.read_file('Interface\\\\Icons\\\\custom_Engineering_60_robot.blp')
Image.open(io.BytesIO(d)).convert('RGBA').save('/tmp/icon.png')
"
```

---

## Ein neues Modell

1. Kandidaten finden — Ascension hat die Creature-Modelle in `patch-CA` bis
   `patch-CZ`. Die Ordnernamen sind sprechend (`mechagonpet`, `clockworkbeagle`,
   `robot_doberman`, `harvestgolempet`, …).
2. In `PETS` setzen:
   - `archive` — welches Ascension-MPQ den Ordner enthält
   - `model` — voller Pfad, z.B. `r"Creature\mechagonpet\mechagonpet.m2"`
   - `texture` — der Texturname **ohne** Pfad und Endung

Zum `texture`-Feld: die meisten portierten Modelle haben eine sogenannte
**Typ-11-Textur**. Das heißt, die Haut steckt nicht im `.m2`, sondern kommt aus
`CreatureDisplayInfo`. Lässt du das Feld leer, ist das Pet ungetextert. Welche
Varianten es gibt, verrät der Dateiname der `.blp` im selben Ordner
(`mechagonpet_junker`, `_brass`, `_silver`). Modelle mit eingebackenen Texturen
— etwa `Gizmo` — brauchen `texture=""`.

Das Skript nimmt automatisch **alle** Dateien aus dem Modellordner mit, also
`.m2`, `.skin`, `.anim` und sämtliche Texturen. Da musst du nichts aufzählen.

---

## Größe

Die Renderhöhe ist ungefähr:

```
Vertex-Bounding-Box des M2 (Offset 0xA0, max Z)  ×  dbc_scale  ×  display_scale
```

Ziel sind **~1.0 Einheiten**; ein Spielercharakter ist ungefähr 2.0 hoch. Das
Skript rechnet dir den Wert beim Bauen aus und gibt ihn aus:

```
Lootbot        model 7501 display 33001 height 1.00
```

`display_scale` steht in `creature_template_model` und ist rein serverseitig.
Zum Nachjustieren brauchst du also **kein** neues Client-Patch — eine Zeile SQL
und ein Serverneustart reichen:

```sql
UPDATE creature_template_model SET DisplayScale = 0.2 WHERE CreatureID = 16549 AND Idx = 0;
```

---

## Name und Tooltip

`spell_name` und `spell_desc` in `PETS`. Beides landet in `Spell.dbc`
(Feld 136 und 170, englische Locale). Rein clientseitig — der Server interessiert
sich nicht dafür, ein Client-Neustart genügt.

Der Name über dem Pet in der Welt kommt dagegen aus `creature_template.name`,
gesetzt in den `*_pet.sql`-Dateien des Moduls. Die Item-Beschreibung in der
Tasche steht in `item_template.description`.

---

## Fallstricke

**Der Client muss beim Installieren geschlossen sein.** WoW lädt
`Cache/WDB/enUS/*.wdb` beim Start in den Speicher und schreibt sie beim Beenden
zurück. Löschst du sie, während der Client läuft, sind sie danach wieder da — mit
den alten Icons und alten Namen. Das Skript prüft das und bricht ab.

Achte darauf, **case-insensitiv** zu prüfen: die Binary heißt `wow.exe` klein,
`pgrep -f "Wow\.exe"` findet sie nicht. Richtig ist `pgrep -if "wow\.exe"`.

**DBCs gehören nach `data/enus/`, nicht nach `data/`.** Die Locale-Archive haben
Vorrang; eine DBC in `data/` wird von `locale-enus.mpq` überstimmt und still
ignoriert. Modelle und Icons dagegen sind locale-neutral und gehören nach `data/`.

**Neue DisplayID braucht eine `creature_model_info`-Zeile.** Sonst bricht
`Creature::InitEntry` ab und das Pet spawnt gar nicht. Die Fehlermeldung im
`Errors.log` nennt `creature_template_model` — das ist die falsche Tabelle und
eine Sackgasse. Das erzeugte SQL setzt die Zeile mit.

**Keine Ascension-Rassen-IDs in den Client.** Ascension hat Rassen bis ID 63,
der 3.3.5a-Client hat Arrays für 21. Alles darüber lässt ihn beim Start mit
`ERROR #132` abstürzen. Betrifft `CharSections.dbc`, `ChrRaces.dbc`,
`CharHairGeosets.dbc` — nicht die Pet-DBCs, aber gut zu wissen.

**Nie Ascensions `patch-M.MPQ` komplett übernehmen.** Das ist deren gesamtes
DBC-Set inklusive `Spell.dbc` und `Item.dbc` und macht den Client gegen
AzerothCore unbrauchbar.

---

## Charakter-Skins von Ascension — verworfen

`build_charpatch.py` und `build_earfix.py` liegen noch im tools-Verzeichnis, sind
aber **nicht installiert**. Der Versuch, Ascensions erweiterte Hautfarben,
Gesichter und Frisuren zu übernehmen, ist an einer Stelle gescheitert, die sich
mit Daten allein nicht lösen lässt. Zur Dokumentation, damit es niemand erneut
versucht:

Ascensions Charaktermodelle deklarieren eine Textur vom Typ 8 (`SKIN_EXTRA`) für
angesetzte Geometrie — Ohren beim Zwerg, Hauer beim Troll, Hörner beim Tauren,
Tentakel beim Draenei. Auf einem unmodifizierten 3.3.5a-Client bleibt die
untexturiert, also weiß oder grün.

Drei Wege wurden probiert, alle drei scheitern:

1. **Textur in `CharSections` verknüpfen.** Funktioniert für Spielercharaktere,
   zerlegt aber die Gesichter der ~13.700 NPCs, die eine vorgerenderte Baked
   Texture benutzen: deren Körper stammt aus dem alten Layout, der Kopf aus dem
   neuen.
2. **Baked Textures leeren**, damit NPCs zur Laufzeit komponieren. Stürzt ab —
   `ERROR #132`, Null-Pointer. Gemessen: **6.340 NPCs** verweisen auf ein Gesicht
   oder einen Bart, für den es **überhaupt keine** `CharSections`-Zeile gibt, auch
   nicht in Blizzards eigener Fassung. Die Bake ist deren einzige Aussehensquelle,
   kein Cache.
3. **Im M2 den Texturtyp 8 auf 1 ändern**, damit die Geometrie den Körperatlas
   nimmt. Kein Absturz, aber die UV-Koordinaten sind für die Kopftextur gemacht —
   das Ergebnis sind falsch eingefärbte Ohren und grüne Hörner.

Ascension löst es mit einer **zusätzlichen Tabelle** `HDCharSections.dbc` (gleiches
Layout wie `CharSections`, 25.544 Zeilen, `tex1` gefüllt) und einer gepatchten
Exe, die pro Charakter entscheidet, welche Tabelle gilt. Ohne diesen Schalter im
Client geht es nicht.

Der Client läuft daher wieder mit seinem eigenen HD-Charakterpatch
(`patch-a.mpq` / `patch-enus-a.mpq`). Die Pets sind davon unberührt.

---

## Wo was liegt

```
modules/mod-madosa/tools/clientpatch/
    build_patches.py    Pets: Modelle, Icons, Tooltips  -> patch-v.mpq + patch-enus-y.mpq
    build_charpatch.py  Charakter-Skins von Ascension   -> patch-enus-z.mpq
    mpq.py              MPQ lesen und schreiben
    dbc.py              DBC lesen, Zeilen anhängen
    out/                Ergebnis, gitignored

modules/mod-madosa/data/sql/db-world/base/pet_ascension_models.sql
    generiert - nicht von Hand editieren, sondern build_patches.py anpassen

<client>/data/patch-v.mpq              Modelle, Texturen, Icons
<client>/data/enus/patch-enus-y.mpq    die fünf gepatchten DBCs
<client>/data/enus/patch-enus-z.mpq    Ascensions Charakter-Skins (build_charpatch.py)
env/dist/data/dbc/*.bak-vanilla        Sicherungen der Original-DBCs
```

Alles ist umkehrbar: die beiden Client-Archive löschen oder auf `.disabled`
umbenennen, die `.bak-vanilla`-Dateien zurückkopieren.
