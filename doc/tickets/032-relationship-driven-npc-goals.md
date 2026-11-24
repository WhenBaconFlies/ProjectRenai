# 032: Relationship-driven NPC goals

**What to build:** Wire `NpcAi.relationship_candidates()` so directed familiarity/affection meters weight free-time goals: NPCs seek friends and love interests and avoid enemies, using the same hangout markers and seeded goal-selection path as v1's interest/mood goals. No complex negotiation or multi-step planning; the v1 interest/mood behavior still works for characters without strong relationships.

**Blocked by:** 022 (Traits + full dialogue content)

**Status:** ready-for-agent

- [ ] `NpcAi` uses directed meters to weight goal selection toward friends/love interests
- [ ] NPCs with strongly negative affection avoid those characters' hangouts
- [ ] Interest/mood goals still fire when no relationship candidate qualifies
- [ ] Selection remains seeded and headless-reproducible
- [ ] No crash when meters are empty or a hangout marker is missing
- [ ] Headless checks demonstrate seek and avoid behavior with authored meters