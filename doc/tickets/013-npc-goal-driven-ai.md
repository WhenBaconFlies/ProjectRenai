# 013: NPC goal-driven AI movement (free time)

**What to build:** During free-time periods, NPCs run goal-driven light AI: choose a goal from traits (interests), current mood, and relationship meters (seek friends/love interests, avoid enemies), move to a destination (hangout spot or another NPC) via `NavigationAgent2D` on the baked navmesh, and re-evaluate goals on period change or completion. No complex planning.

**Blocked by:** 012 (NPC spawning & scheduling)

**Status:** done

- [x] NPCs select a goal from interests and mood (relationship-meter goals deferred to 014/015 per recorded decision)
- [x] NPCs move toward their goal using `NavigationAgent2D`
- [x] Goals re-evaluate on period change and on goal completion
- [x] Movement is smooth and avoids obstacles on the baked navmesh
- [x] NPCs do not get stuck or fail to reach their destination under normal conditions