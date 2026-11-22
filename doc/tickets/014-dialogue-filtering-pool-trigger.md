# 014: Dialogue filtering + pool + player trigger

**What to build:** A pair-agnostic dialogue pipeline: an `InteractionComponent` triggers on `Area2D` proximity + E keypress (player-initiated), filters all `DialogueTopic` resources whose conditions pass (mood/interest/trait/familiarity thresholds, required stat), and presents a random pool of 3–5 topics. The player can select one. No resolution yet — just filtering, pooling, and display.

**Blocked by:** 013 (NPC goal-driven AI), 006 (DialogueTopic schema)

**Status:** ready-for-agent

- [ ] Pressing E near an NPC opens a dialogue pool of 3–5 topics
- [ ] Topics are filtered by conditions (mood, interest, trait, familiarity, required stat)
- [ ] The pool is randomized within eligible topics
- [ ] Player can select a topic from the pool
- [ ] If no topics are eligible, the interaction is handled gracefully (no crash, sensible fallback)
- [ ] Trigger only fires when an NPC is in proximity