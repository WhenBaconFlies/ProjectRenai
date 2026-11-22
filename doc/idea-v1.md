# Project Renai — Specification v1

Derived from `doc/idea-v0.md` + decisions in `doc/idea-v0-decisions.md`.
Engine: Godot 4.2 | Platform: Windows desktop | Language: GDScript + C#.

## 1. Goal
A modular 2D quarter-view life-simulation game where the player lives a school year, interacting with simulated NPCs whose familiarity/affection meters drive relationships (stranger/friend/enemy/lover), with emphasis on romance and interacting character traits. v1 ships the core loop.

## 2. Architecture (Godot)

### Folder layout
- `res://` root
  - `scenes/` — `.tscn` scenes (MainMenu, NewGame, LoadGame, CreateMenu, ModsMenu, Options, Game)
  - `scripts/` — GDScript/C# scripts
  - `resources/` — `.tres` data (characters, maps, traits, items)
  - `assets/` — sprites, audio, fonts
  - `mods/` — mod folders (each with `mod.json`)
  - `saves/` — runtime save files (user:// in production)

### Autoloads (singletons)
- `GameManager` — global state, current save, scene transitions
- `SaveManager` — save/load, slot management
- `TimeManager` — day clock, calendar, period tracking
- `ModLoader` — scans `res://mods/`, registers resources/scripts
- `AudioManager` — music/SFX, volume
- `LocalizationManager` — string tables (English v1)

### Scene flow
MainMenu → NewGame (map → save options → character) → Game (play) → (autosave/manual at day end) → next day or quit.
LoadGame → Game. CreateMenu / ModsMenu / Options reachable from MainMenu.

### Data format
- Characters, maps, traits, items: Godot Resources (`.tres`), typed with `class_name`.
- Mods: folder with `mod.json` + `.tres`/scripts; loaded by ModLoader at startup.
- Saves: file-based (user://), unlimited slots.

## 3. Main Menu
Buttons: New Game, Load Game, Create Menu, Mods Menu, Options, Quit.

## 4. New Game Flow
1. Choose map (v1: single testing map).
2. Save options page: NPC count (default 30), stat settings, schedule changes, toggles (trait points on/off, relationship feedback on/off, etc.).
3. Choose character or create new one (same controls as Create Menu).
4. Start game: player spawns at school entrance, first day begins.

## 5. Load Game
List saved games; load or delete each.

## 6. Create Menu
### Character creation
- Name, appearance (mix-and-match: hair, eyes, mouth, skin tone, outfit).
- Traits: skills, interests, dislikes, personality. 10 trait points default (disable-able). Positive traits cost points; negative grant points.
- Traits set starting stats (STR/DEX/CON/INT/WIS/CHA) and modify growth rates.
- Gender + orientation (for romance eligibility).
### Map editor
- Build menu: place walls, furniture, floors, stairs, etc. in open editor.
- Saved to its own `.tres` file.

## 7. Mods Menu
List installed/enabled mods from `res://mods/`. Each mod has `mod.json`.

## 8. Options Menu
Volume, language (English v1), resolution, and other game-wide options.

## 9. Gameplay

### Calendar
- School year: configurable days (default 365). Weekends, summer, winter, and other breaks are not played as normal days; instead a short choice menu (Study, Hang out, Rest, Hobby) modifies stats/relationships.

### Day loop
- 4 class periods per day; class time mostly skipped (attendance recorded; grade per class from attendance + INT/WIS; small stat bonus).
- Free time between periods for interactions.
- Day length: 15 minutes real time; player can skip to next period.
- Save prompt at end of day (autosave + manual, unlimited slots).

### Simulation
- ~30 NPCs (configurable) each with stats, traits, mood (0–100), schedule (period→location), and relationship meters toward others (Familiarity 0–100, Affection −100..100).
- NPCs follow simple daily routines; move between classes per schedule.
- Player tracked similarly but free to choose interactions; available choices gated by player stats + relationship level.

### Interaction
- Approach NPC, press E. Dialogue pool of 3–5 randomized options selected by mood, interests, traits, familiarity.
- Resolution: stat check (e.g., CHA) + randomness; success raises affection, failure lowers mood.
- Relationship meters update; type derived: Stranger (Fam<20), Friend (Fam>=20 & Aff>=20), Enemy (Aff<=-20), Lover (Fam>=60 & Aff>=60 & mutual orientation/gender).
- Romance is mutual: both orientation and affection must align; rejection possible.

### Stats & Growth
- STR/DEX/CON/INT/WIS/CHA gate dialogue options and affect success chance.
- Growth via break activities + interactions (study→INT, socialize→CHA, etc.); traits modify growth rate.

### UI
- Simple but cute. Minimap for navigation. Location labels on entering areas (optional; minimap primary).
- Relationship meter change shown after interaction (toggle, default on).
- No day-end summary screen; save prompt only.

### Audio
- Music + SFX. Volume controlled in Options.

## 10. Open / Deferred (post-v1)
- Exact trait list and point costs (data files).
- Exact resource schema field lists.
- NPC pathfinding implementation.
- Performance for >30 NPCs.
- Additional languages.
- Full academic system, combat, deeper AI.