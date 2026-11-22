# 016: NPC-initiated interactions

**What to build:** An NPC with sufficient outgoingness may initiate an interaction with the player or another NPC when not already pursuing a goal, choosing the target by outgoingness + familiarity. The initiator receives the same filtered dialogue pool as a player would and picks one option at random; the threshold roll and deltas apply to both parties' directed meters. The pipeline stays pair-agnostic `(initiator_id, target_id)`.

**Blocked by:** 015 (Threshold resolution + deltas + meter/mood updates + feedback)

**Status:** ready-for-agent

- [ ] An NPC initiates an interaction during free time when not busy
- [ ] Target selection weighs outgoingness and familiarity
- [ ] The NPC picks randomly from the eligible pool
- [ ] Threshold roll and deltas apply to both parties' directed meters
- [ ] Initiation can target the player or another NPC
- [ ] No crash or duplicate interaction if the target is already interacting