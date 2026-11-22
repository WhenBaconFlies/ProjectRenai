# 019: ChunkManager + tiered NPC simulation

**What to build:** A `ChunkManager` autoload that owns tier assignment (player-centered, with hysteresis), promotion/demotion (promotion interpolates position over ~0.5s), and the NPC tick scheduler that ticks NPCs at tier-appropriate rates. `NpcInstance` gains a runtime-only `tier` (close/near/far) and `coarse_position` (far); identity/state always preserved. Far NPCs use coarse (straight-line) pathfinding and tick rarely with large dt. Includes config-level support for tier radii and tick rates (defaults provided; Options UI wiring deferred). Interaction guard: only close-tier NPCs are interactable; attempting to interact with a near NPC promotes it first.

**Blocked by:** 018 (Day-loop integration & acceptance verification), 020 (Chunk-aware map renderer + chunk grid) [schema dependency]

**Status:** ready-for-agent

- [ ] `ChunkManager` autoload exists and assigns tiers (close/near/far) based on player position
- [ ] Hysteresis: promote at inner radius, demote at outer radius + 1 chunk buffer
- [ ] Promotion interpolates position over ~0.5s; demotion is instant (state preserved)
- [ ] NPC tick scheduler ticks NPCs at tier-appropriate rates (close = every frame/period, near = every N frames/seconds, far = every 5–10s with large dt)
- [ ] Far NPCs retain identity/state and use coarse (straight-line) pathfinding
- [ ] `NpcInstance` has runtime-only `tier` and `coarse_position` fields (not persisted)
- [ ] Config-level support for tier radii and tick rates with sensible defaults
- [ ] Interaction guard promotes a near NPC to close on interaction attempt
- [ ] Only close-tier NPCs are interactable in the steady state
- [ ] Tiers are recomputed from player spawn position on load
- [ ] No crash or thrashing at tier boundaries under normal movement