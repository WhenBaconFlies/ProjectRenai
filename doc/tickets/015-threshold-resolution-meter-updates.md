# 015: Threshold resolution + deltas + meter/mood updates + feedback

**What to build:** Resolve a selected dialogue topic via a threshold check (`stat + (familiarity/10) + random(0..5) >= difficulty`, difficulty may incorporate recipient stats/traits). Margin scales the affection delta. Apply success/failure affection, familiarity, and mood deltas to both parties' directed meters. Show feedback (meter change) after the interaction, default on.

**Blocked by:** 014 (Dialogue filtering + pool + player trigger)

**Status:** ready-for-agent

- [ ] Selecting a topic runs the threshold check and reports success/failure
- [ ] Margin scales the affection delta
- [ ] Affection, familiarity, and mood deltas apply to both initiator and recipient meters
- [ ] Relationship type is re-derived after meters update (Stranger/Friend/Enemy/Lover)
- [ ] Feedback (meter change) is shown after interaction by default
- [ ] Feedback toggle (save option) is respected