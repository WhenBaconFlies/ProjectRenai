# 022: Traits + full dialogue content

**What to build:** Author ~15–20 new traits across skills/interests/dislikes/personality (with point costs and tags) and ~40–60 dialogue topics total across greetings, player topics, and responses — including one authored default response per topic for the layered fallback and at least one greeting per relationship band. All content is `.tres` under `resources/`, registered as base content by `ModLoader` alongside existing characters and topics, so a conversation can draw from real authored data and tags feed greeting variation, response filtering, and NPC goals.

**Blocked by:** 021 (Dialogue greeting + response schemas + registry buckets)

**Status:** ready-for-agent

- [ ] ~15–20 new traits exist as `.tres` across all four categories with point costs and tags
- [ ] ~40–60 dialogue topics exist as `.tres` across greetings, topics, and responses
- [ ] Each topic has at least one authored default response (blank band/outcome)
- [ ] Greetings cover the four variation factors (relationship, mood, period, traits/interests)
- [ ] All content loads through `ModLoader` base registration with no duplicate-id conflicts
- [ ] A smoke check shows at least one eligible greeting and response for the default player/NPC pair