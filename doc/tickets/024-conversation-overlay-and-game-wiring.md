# 024: ConversationUI overlay + Game wiring

**What to build:** A `ConversationUI` Control overlay at the bottom of the screen — semi-transparent, showing speaker name and spoken line with stacked numbered choices, over the still-visible school world, with reserved (unimplemented) portrait slots for both speakers. Wire it into `Game.gd` with the pure `Conversation` helper: player-initiated flows show greeting → topic → reactive NPC line → optional second exchange → leave, with feedback after each turn. NPC-initiated conversations keep their unique shape: the NPC speaks its own topic with no deltas, the player gets 2–3 filtered reply options (response text as the player's line), the reply resolves with the player as initiator, then the talk ends. Input is locked during a conversation; the free-time gate is a condition/callable, not a hardcoded state check.

**Blocked by:** 023 (Conversation helper + filter/resolver extensions)

**Status:** ready-for-agent

- [ ] A player-initiated talk shows a greeting, accepts a topic, shows a reactive NPC line, and allows at most two picks
- [ ] The overlay is semi-transparent at the bottom with speaker name and choices; the world remains visible behind it
- [ ] Portrait slots exist as placeholders but render no art
- [ ] Feedback appears after each turn and the relationship type updates visibly
- [ ] An NPC-initiated talk speaks its topic with no deltas, offers 2–3 filtered replies, resolves the player's reply, and ends
- [ ] The player's input is locked for the duration of either conversation shape
- [ ] NPC initiation only fires in free time via a callable/condition, with no crash when no candidates exist
- [ ] The existing one-pick close path is fully replaced