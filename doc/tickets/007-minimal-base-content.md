# 007: Minimal base content (authored resources)

**What to build:** Author a minimal set of base resources in the Godot editor using the schemas from 004–006: one map, two characters, a handful of traits, two to three dialogue topics, and a few items. This gives every later ticket real data to load and test against.

**Blocked by:** 004 (CharacterTemplate + Trait schemas), 005 (Item + Map schemas), 006 (DialogueTopic schema)

**Status:** ready-for-agent

- [ ] At least one `Map` `.tres` exists with tiles, placed objects, and a spawn point
- [ ] At least two `CharacterTemplate` `.tres` files exist with traits, stats, and appearance
- [ ] At least one `Trait` `.tres` per category (skill, interest, dislike, personality)
- [ ] At least two `DialogueTopic` `.tres` files with conditions and deltas
- [ ] At least two `Item` `.tres` files
- [ ] All resources load in the editor without errors