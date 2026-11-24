# 021: Dialogue greeting + response schemas + registry buckets

**What to build:** Add two new `.tres` resource types alongside the existing `DialogueTopic`: `DialogueGreeting` (id, text, eligibility by relationship/mood/period/traits, weight) and `DialogueResponse` (id, text, topic id, outcome, relationship band of the five derived types, and its own optional roll fields: checked stat, difficulty, success/failure affection/familiarity/mood deltas). `ModLoader` gains `TYPE_GREETING` and `TYPE_RESPONSE` buckets and registers authored instances by stable id with add-only duplicate rules. A developer can author and load all three dialogue resource types in the editor and via the registry.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `DialogueGreeting` resource class exists with identity, text, eligibility, and weight fields
- [ ] `DialogueResponse` resource class exists with identity, text, topic id, outcome, relationship band, and optional roll/delta fields
- [ ] `ModLoader` has `TYPE_GREETING` and `TYPE_RESPONSE` buckets with add-only registration
- [ ] A `.tres` of each new type can be created, saved, and round-tripped in the editor
- [ ] Empty roll fields on a `DialogueResponse` are documented as "line-only reaction"
- [ ] All fields are typed and documented with comments