# 014: Dialogue filtering + pool + player trigger

**What to build:** A pair-agnostic dialogue pipeline: an `InteractionComponent` triggers on `Area2D` proximity + E keypress (player-initiated), filters all `DialogueTopic` resources whose conditions pass (mood/interest/trait/familiarity thresholds, required stat), and presents a random pool of 3–5 topics. The player can select one. No resolution yet — just filtering, pooling, and display.

**Blocked by:** 013 (NPC goal-driven AI), 006 (DialogueTopic schema)

**Status:** done

- [x] Pressing E near an NPC opens a dialogue pool of 3–5 topics
- [x] Topics are filtered by conditions (mood, interest, trait, familiarity, required stat)
- [x] The pool is randomized within eligible topics
- [x] Player can select a topic from the pool
- [x] If no topics are eligible, the interaction is handled gracefully (no crash, sensible fallback)
- [x] Trigger only fires when an NPC is in proximity

**User-confirmed additions:** Cancel option (Esc/button) ends the interaction without a pick; the player stays movement-locked and the target NPC stays frozen+busy until selection or cancel; the clock and other NPCs keep running; E works at any time of day, not only free time. See the Ticket 014 section of `doc/idea-v1-decisions.md`.

**Verification:** 61/61 headless checks passed (`ALL_014_CHECKS_PASSED`); code review at `doc/code-review/codereview-ticket-014-dialogue-filtering-pool-trigger.md` (5 findings, all fixed and re-verified).
