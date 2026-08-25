# Items erstellen und die Welt bearbeiten

Kurzanleitung für zwei Dinge, die auf diesem Server oft zusammen gebraucht
werden: eigene Items anlegen und NPCs oder Objekte in der Welt versetzen.

Für Aussehen und Tooltip der Companion-Pets siehe `PETS-ANPASSEN.md`.

---

## Teil 1 — Neue Items

### Du brauchst kein Client-Patch

Das ist der wichtigste Punkt. Der Client fragt Items, die er nicht kennt, beim
Server ab (`SMSG_ITEM_QUERY_SINGLE_RESPONSE`). Eine Zeile in `item_template`
in `acore_world` genügt — Name, Beschreibung, Werte, alles kommt vom Server.

Die einzige Ausnahme ist `displayid`. Der bestimmt **Icon und 3D-Modell** und
muss auf eine vorhandene Zeile in `ItemDisplayInfo.dbc` zeigen. Davon gibt es
rund 58.000. Nur wenn du ein *eigenes* Icon willst, brauchst du ein Client-Patch
— dafür ist `modules/mod-madosa/tools/clientpatch/build_patches.py` da.

### Ein passendes Aussehen finden

Such dir ein vorhandenes Item, das so aussieht wie deines aussehen soll, und
übernimm dessen `displayid`:

```sql
SELECT entry, name, displayid, Quality FROM item_template
WHERE name LIKE '%Sword%' AND Quality >= 3 LIMIT 20;
```

### ID-Bereich

`item_template` geht aktuell bis **56806** — das ist exakt Blizzards Maximum,
es gibt also noch keine eigenen Items. Nimm **90000+**, dann kollidierst du
weder mit Blizzard noch mit künftigen AzerothCore-Updates.

Zum Vergleich die anderen Tabellen (Stand: diese Datenbank):

| Tabelle | höchste ID | Einträge |
|---|---|---|
| `item_template` | 56.806 | 46.096 |
| `creature_template` | 3.460.603 | 30.202 |
| `gameobject_template` | 401.007 | 21.584 |
| `quest_template` | 109.684 | 9.505 |

mod-madosa benutzt für eigene Kreaturen den Bereich **900300+**.

### Das SQL

```sql
DELETE FROM `item_template` WHERE `entry` = 90001;
INSERT INTO `item_template` (`entry`,`class`,`subclass`,`name`,`displayid`,`Quality`,
       `Flags`,`BuyPrice`,`SellPrice`,`InventoryType`,`ItemLevel`,`maxcount`,`stackable`,
       `spellid_1`,`spelltrigger_1`,`description`)
VALUES (90001,15,0,'Mein Item',59497,4,0,0,0,0,80,1,1,0,0,'Beschreibung');
```

Die wichtigsten Spalten:

| Spalte | Bedeutung |
|---|---|
| `class` / `subclass` | 15/0 = Verschiedenes, 2 = Waffe, 4 = Rüstung, 0 = Verbrauchsgut |
| `Quality` | 0 grau, 1 weiß, 2 grün, 3 blau, 4 lila, 5 orange |
| `InventoryType` | 0 = nicht anlegbar, 1 = Kopf, 5 = Brust, 13 = Einhand … |
| `spellid_1` + `spelltrigger_1` | Zauber am Item; Trigger 0 = bei Benutzung, 1 = dauerhaft, 6 = lehrt den Zauber |
| `maxcount` / `stackable` | 0 = unbegrenzt |

Ablage: eigene Sachen ins Modul unter
`modules/mod-madosa/data/sql/db-world/base/`, Core-nahes über
`data/sql/updates/pending_db_world/create_sql.sh`. Immer `DELETE` vor `INSERT`
— das prüft `apps/codestyle/codestyle-sql.py`.

### Testen

```
.additem 90001
```

### Zwei Fallstricke

**Es gibt kein `.reload item_template`.** Nach jeder Änderung an einem Item
musst du den worldserver neu starten. (`.reload npc_vendor` und
`.reload creature_template <entry>` existieren dagegen — letzteres lädt
allerdings *nur* `creature_template`, nicht `creature_template_model`.)

**Der Client cached Items.** `Cache/WDB/enUS/itemcache.wdb` merkt sich jede
Server-Antwort. Änderst du Name, Icon oder Beschreibung eines Items, das du
schon einmal im Spiel gesehen hast, zeigt der Client stur die alte Fassung.

Cache löschen — aber **nur bei geschlossenem Client**:

```fish
pgrep -if "wow\.exe"    # muss leer sein, achte auf das -i: die Binary heißt klein
rm ~/Games/world-of-warcraft-wrath-of-the-lich-king/drive_c/world_of_warcraft_wrath_of_the_lich_king/Cache/WDB/enUS/*.wdb
```

WoW lädt die `.wdb`-Dateien beim Start in den Speicher und schreibt sie beim
Beenden zurück. Löschst du sie während der Client läuft, sind sie danach wieder
da — mit den alten Daten.

---

## Teil 2 — Die Welt bearbeiten

**Die GM-Befehle sind das Werkzeug, und sie schreiben direkt in die Datenbank.**
Einen separaten 3D-Editor für Server-Spawns gibt es für AzerothCore nicht — er
wird auch nicht gebraucht, weil du im Spiel selbst dein Editor bist.

### Vorbereitung

```
.account set gmlevel <accountname> 3 -1      # einmalig, -1 = alle Realms
.gm on
.gm fly on
```

### Einen NPC versetzen

Beispiel: einer der Mount-Händler. Die liegen als `guid` 5392001–5392008 in der
`creature`-Tabelle.

Stell dich dorthin, wo er stehen soll, klick den NPC an, dann:

```
.npc move
```

Fertig. `HandleNpcMoveCommand` in `src/server/scripts/Commands/cs_npc.cpp` nimmt
deine aktuelle Position, setzt die Kreatur um und führt
`WORLD_UPD_CREATURE_POSITION` aus — **persistent, überlebt den Neustart**. Ohne
Anklicken geht auch `.npc move 5392001` mit der guid.

### Die nützlichen Befehle

| Befehl | Wirkung |
|---|---|
| `.npc add <entry>` | Spawnt an deiner Position, legt eine `creature`-Zeile an |
| `.npc move [guid]` | Verschiebt an deine Position, speichert |
| `.npc delete [guid]` | Entfernt den Spawn |
| `.npc info` | entry, guid, displayid, faction, flags des angeklickten NPC |
| `.npc near [radius]` | Listet Spawns in der Nähe samt guid |
| `.npc model <id>` | Aussehen ändern |
| `.npc flag <mask>` | npcflag, z.B. Händler oder Questgeber |
| `.npc add item <item>` | Ware zum angeklickten Händler hinzufügen |
| `.npc delete item <item>` | Ware wieder entfernen |
| `.npc spawntime <sek>` | Respawn-Zeit |
| `.gobject add <entry>` | Objekt spawnen |
| `.gobject move` / `.gobject turn` | Objekt versetzen / drehen |
| `.gobject near [radius]` | Objekte in der Nähe |
| `.go xyz <x> <y> <z> [map]` | Hinspringen |
| `.gps` | Eigene Koordinaten, Map und Zone ausgeben |
| `.lookup creature <name>` | entry zu einem Namen finden |

`.gps` ist praktisch, wenn du Koordinaten für ein SQL brauchst, statt per
Befehl zu spawnen.

### Direkt per SQL

Wenn du lieber in der Datenbank arbeitest — die Spawn-Tabelle heißt `creature`,
die Spalte für den Kreaturtyp heißt `id` (nicht `entry`, das ist
`creature_template`):

```sql
SELECT c.guid, c.id, ct.name, c.map,
       ROUND(c.position_x,1) x, ROUND(c.position_y,1) y, ROUND(c.position_z,1) z
FROM creature c JOIN creature_template ct ON ct.entry = c.id
WHERE ct.name LIKE '%Special Vendor%';

UPDATE creature SET position_x = -8830.0, position_y = 620.0, position_z = 94.0
WHERE guid = 5392001;
```

Nach einem SQL-`UPDATE` braucht es einen Serverneustart oder `.reload` — beim
GM-Befehl nicht, der ändert die laufende Welt gleich mit.

---

## Teil 3 — Werkzeuge

### Was du schon hast

**mod-homebrew-gm** — GM-Werkzeuge hinter einer Oberfläche im Spiel, mit
RBAC-Prüfung, Item- und Zaubersuche, Teleport, Item-Vergabe. Das ist dein
Frontend für vieles aus Teil 2.

**mod-live-dashboard** — zeigt Spieler und Bots live auf einer Zonenkarte. Die
Mechanik (Positionen alle 2 s in `live_player_positions`) ließe sich um
NPC-Spawns erweitern; dann hättest du eine Weltkarte mit deinen Händlern drauf.

**smpq** und **StormLib** (`/usr/lib/libstorm.so`) — für alles, was in
MPQ-Archive schaut:

```fish
smpq --list <archiv.mpq>
smpq --extract <archiv.mpq> "Interface/Icons/foo.blp"    # Schrägstrich, nicht Backslash
```

**modules/mod-madosa/tools/clientpatch/** — die MPQ- und DBC-Pipeline, falls du
doch mal ein eigenes Icon oder Modell brauchst.

### Empfehlenswert extern

**Keira3** ist das Werkzeug, das hier wirklich fehlt: der offizielle
AzerothCore-Datenbankeditor als Web-App. Formulare für `item_template`,
`creature_template`, Quests, Loot-Tabellen, SmartAI und Gossip, mit Dropdowns
statt Spaltennummern, und SQL-Export. Für Items und Quests deutlich angenehmer
als SQL von Hand. Läuft lokal gegen `acore_world`.

**Noggit Red** wird oft genannt, löst aber ein anderes Problem: das ist ein
Terrain-Editor für die ADT-Dateien des *Clients*. Damit modellierst du
Landschaft und platzierst Doodads — rein clientseitig. Für NPC-Spawns nutzlos,
die kennt nur der Server.

---

## Merkzettel

- Neues Item → nur `item_template`, kein Client-Patch, aber **Serverneustart**
- Eigenes Icon → zusätzlich `ItemDisplayInfo.dbc` über `build_patches.py`
- Item sieht falsch aus → `itemcache.wdb` löschen, Client vorher schließen
- NPC versetzen → `.npc move`, sofort und dauerhaft
- Spawn-Tabelle ist `creature`, Spalte `id`; `creature_template` hat `entry`
- `pgrep -if`, nicht `pgrep -f` — die Binary heißt `wow.exe` klein
