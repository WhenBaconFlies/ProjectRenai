# 006: DialogueTopic schema

**What to build:** Define the `DialogueTopic` resource class (`.tres`) with id, text, conditions (mood/interest/trait/familiarity thresholds, required stat), checked stat, difficulty, success/failure affection deltas, familiarity delta, and mood delta. A developer should be able to author dialogue topics as data.

**Blocked by:** 001 (Project scaffolding)

**Status:** ready-for-agent

- [ ] `DialogueTopic` resource class exists with all specified fields
- [ ] A `.tres` can be created and saved in the editor without errors
- [ ] Fields are typed and documented with comments
- [ ] Conditions and deltas are clearly separated (success vs. failure variants)