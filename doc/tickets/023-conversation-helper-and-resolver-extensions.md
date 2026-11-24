# 023: Conversation helper + filter/resolver extensions

**What to build:** A pure `Conversation` (`RefCounted`) helper owning session state — phase (GREETING/TOPIC/RESPONSE/FOLLOWUP/DONE), turn count (max 2 player picks), initiator/target ids, seeded RNG — with no scene-tree or autoload references. Extend `DialogueFilter` with greeting selection and response selection (including the layered fallback: exact → topic default → generic authored → generated) and `DialogueResolver` with `resolve_response()` reusing the existing roll, margin scaling, recipient modifiers, dual-party meter/mood writes, and relationship derivation. The responder's derived relationship type toward the speaker keys a response. This ticket makes the full conversation rules verifiable headlessly, before any UI exists.

**Blocked by:** 021 (Dialogue greeting + response schemas + registry buckets), 022 (Traits + full dialogue content)

**Status:** ready-for-agent

- [ ] `Conversation` is pure (no scene tree/autoload globals), seeded, and headless-instantiable
- [ ] Phase flow supports greeting → topic → response → optional follow-up → done, with max 2 player picks
- [ ] Greeting selection filters by all four factors with a safe any-eligible fallback
- [ ] Response selection applies the layered fallback chain with no dead-end
- [ ] `resolve_response()` resolves a response with roll fields and produces line-only outcomes when fields are empty
- [ ] The 5-type relationship band is derived for the responder toward the speaker
- [ ] Headless checks cover turn limits, fallbacks, both-party deltas, and seeded determinism