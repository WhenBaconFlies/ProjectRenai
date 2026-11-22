# Project Renai — Clarification Decisions (v0 → v1)

Source idea: `doc/idea-v0.md`
Output spec: `doc/idea-v1.md`

## Decisions

### Platform & Stack
- Engine: Godot 4.2 (`config/features = PackedStringArray("4.2", "Forward Plus")`).
- Language: Both GDScript (gameplay/UI) and C# (data-heavy systems).
- Target platform (v1): Windows desktop.

### Scope of v1
- Milestone: Core loop only — one map, player + a few NPCs, free movement, one interaction type (talk), save/load day. Full baseline described in spec but implemented incrementally.

### Core Loop
- Movement/interaction: Free movement; press interact key (E) to talk to nearby NPCs.
- Time: Real-time clock with skip-to-next-period; default day length 15 minutes.
- Camera: Follows player with smoothing.
- Navigation aid: Minimap.

### Simulation Depth (v1)
- NPC depth: Light — stats, traits, schedule, relationship meters, simple routines.
- NPC count: Configurable in save options; default 30. Optimize for larger schools.
- NPC schedules: Yes — list of (period, location) entries; NPCs move between classes.
- Player as NPC: Stats/schedule/relationships tracked like an NPC, but player is free to interact; choices limited by stats/relationship.
- Mood: Numeric 0–100; affects dialogue pool and stat checks.
- Relationship feedback: Toggle in save options; default ON (meter change shown after interaction).

### Relationship System
- Meters: Familiarity 0–100, Affection −100 to 100.
- Type derivation: Familiarity gates, Affection sign/direction:
  - Stranger if Familiarity < 20.
  - Friend if Familiarity >= 20 and Affection >= 20.
  - Enemy if Affection <= −20.
  - Lover if Familiarity >= 60 and Affection >= 60 and mutual orientation/gender compatibility.
- Romance: Orientation + gender constraints; mutual (both characters' orientation/affection matter; rejection possible).

### Character System
- Stats (6): STR, DEX, CON, INT, WIS, CHA.
- Trait categories (4): Skills, Interests, Dislikes, Personality.
- Trait point budget: 10 default; disable-able in settings. Positive traits cost points; negative grant points.
- Trait → stat link: Traits affect both starting stats and stat growth rates.
- Stat growth: Through break activities + interactions; traits modify growth rate.
- Appearance (v1): Hair, eyes, mouth, skin tone, outfit (mix-and-match).

### Academics (v1)
- Basic: Grade per class from attendance + stat (INT/WIS); grade grants small stat bonus.
- Class periods: 4 per school day. Class time mostly skipped (attendance recorded).

### Calendar
- School year length: Configurable; default 365 days.
- Breaks: Summer, winter, weekends and other breaks skipped as normal gameplay days, but present a short choice menu (Study, Hang out, Rest, Hobby) whose outcomes change stats/relationships.

### Interaction
- Dialogue pool: 3–5 randomized options per interaction, selected by mood, interests, traits, familiarity.
- Resolution: Stat check (e.g., CHA) + randomness; success improves affection, failure worsens mood.
- Stat effects: Stats gate available dialogue options and affect success chance.

### Save System
- Mode: Autosave + manual.
- Slots: Unlimited (file-based).
- Day-end summary: None; just save prompt.
- Progress saved: End of every day.

### Audio & Localization
- Audio (v1): Music + SFX.
- Localization (v1): English only; framework ready for more.

### Modding
- Mod folder: `res://mods/`.
- Integration: Resource + script drop-in — mods add `.tres` resources and GDScript/C# scripts; game scans and registers them.
- Manifest: Each mod folder must contain `mod.json` (name, version, author, entry scripts).
- Mod menu: View installed and enabled mods.

### Data Format
- Characters/maps/mods: Godot Resources (`.tres`).
- Mod metadata: `mod.json`.

### Architecture
- Spec includes defined folder/scene architecture (autoloads, scene structure, resource folders) — see idea-v1.md §Architecture.

### UI
- Style: Simple but cute.
- Main menu buttons: New Game, Load Game, Create Menu, Mods Menu, Options, Quit.
- New Game flow: Choose map → save options (NPC count, stat settings, schedule, toggles) → choose/create character (same controls as Create Menu) → play.
- Load Game: Load or delete saved games.
- Create Menu: Create characters (name, appearance, traits) or maps (map editor with build menu: walls, furniture, floors, stairs, etc.; saved to its own file).
- Options Menu: Volume, language, resolution (and other game-wide options).

### Open / Deferred
- Exact relationship meter thresholds beyond the recommended defaults — tune during playtesting.
- Exact trait list and point costs — defined in data files during implementation.
- Exact map/character resource schema field lists — defined in implementation; format is `.tres`.
- NPC pathfinding/physics — implementation detail.
- Performance targets for >30 NPCs — profile during development.