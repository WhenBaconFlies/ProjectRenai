# 032: Relationship-driven NPC goals

**What to build:** Wire `NpcAi.relationship_candidates()` so directed familiarity/affection meters weight free-time goals: NPCs seek friends and love interests and avoid enemies, using the same hangout markers and seeded goal-selection path as v1's interest/mood goals. No complex negotiation or multi-step planning; the v1 interest/mood behavior still works for characters without strong relationships.

**Blocked by:** 022 (Traits + full dialogue content)

**Status:** complete

- [x] `NpcAi` uses directed meters to weight goal selection toward friends/love interests
- [x] NPCs with strongly negative affection avoid those characters' hangouts
- [x] Interest/mood goals still fire when no relationship candidate qualifies
- [x] Selection remains seeded and headless-reproducible
- [x] No crash when meters are empty or a hangout marker is missing
- [x] Headless checks demonstrate seek and avoid behavior with authored meters