# 015: Threshold resolution + deltas + meter/mood updates + feedback

**What to build:** Resolve a selected dialogue topic via a threshold check (`stat + (familiarity/10) + random(0..5) >= difficulty`, difficulty may incorporate recipient stats/traits). Margin scales the affection delta. Apply success/failure affection, familiarity, and mood deltas to both parties' directed meters. Show feedback (meter change) after the interaction, default on.

**Blocked by:** 014 (Dialogue filtering + pool + player trigger)

**Status:** done

- [x] Selecting a topic runs the threshold check and reports success/failure
- [x] Margin scales the affection delta
- [x] Affection, familiarity, and mood deltas apply to both initiator and recipient meters
- [x] Relationship type is re-derived after meters update (Stranger/Acquaintance/Friend/Enemy/Lover — Acquaintance added by user decision)
- [x] Feedback (meter change) is shown after interaction by default
- [x] Feedback toggle (save option) is respected

**Verification:** 64/64 headless Godot 4.2.1 checks pass (`ALL_015_CHECKS_PASSED`) covering all six criteria; design and acceptance mapping in `doc/tickets/015-threshold-resolution-meter-updates-design.md`; implementation decisions in `doc/idea-v1-decisions.md` (Ticket 015 section).