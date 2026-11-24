# Code Review: ticket/021-dialogue-greeting-response-schemas vs master

- **Branch:** ticket/021-dialogue-greeting-response-schemas (local commit `554699e`)
- **Base:** master (merge-base: `240e37fbda32755705901dfcb8ea9fceafc944ab`)
- **Changed files:** 14 (639 insertions, 11 deletions)
- **Findings:** 7 (Critical: 0, High: 0, Medium: 2, Low: 5)
- **Dropped claims:** 1 (unsupported — see Evidence Audit)

## Findings

### 1. [Medium][Architecture] Decision record overstates resolver reuse
- **Location:** `doc/idea-v2-decisions.md:72` (review-time text); `scripts/DialogueResolver.gd:63,79`; `scripts/DialogueResponse.gd:1-2`
- **Evidence:** The decision said the response roll fields were "identical names and semantics to `DialogueTopic` so ticket 023 can reuse `DialogueResolver` unchanged." `DialogueResolver.resolve()` is statically typed `topic: DialogueTopic` (`:63`) and dereferences `topic.recipient_modifiers` (`:79`). `DialogueResponse extends Resource` directly and has no `recipient_modifiers` field, so passing one is a compile error even before the missing property is reached.
- **Problem:** An implementer of ticket 023 following that sentence would attempt an impossible call, then discover the response's own roll fields are not consumed.
- **Recommendation:** State that ticket 023 must extend the resolver with a response-aware entry point (or roll-fields provider) and that response-owned roll fields are independent of the keyed topic's values.
- **Resolution:** Fixed — decision record now names the static-typing and `recipient_modifiers` blockers explicitly; `DialogueResponse.gd` comment updated to say the resolver must be generalized.

### 2. [Medium][Architecture] "Line-only mirrors DialogueTopic" is factually inverted
- **Location:** `doc/idea-v2-decisions.md:71`; `scripts/DialogueResponse.gd:14-16`
- **Evidence:** Both texts called empty `checked_stat` a mirror of `DialogueTopic`'s "empty = no stat bonus." In `DialogueResolver.gd:102-103` an empty `checked_stat` only zeroes `stat_bonus`; the die is still rolled (`:112`), success computed (`:114-115`), and deltas applied (`:123-140`). In `DialogueResponse` the same condition suppresses the entire roll via `is_line_only()` (`:80-83`). `is_line_only()` was not called anywhere in the branch.
- **Problem:** Describing a deliberate divergence as a mirror hides the fact that ticket 023 must gate on `is_line_only()` before resolving; otherwise a line-only response with authored deltas would change meters.
- **Recommendation:** Document the divergence and require the gate in ticket 023.
- **Resolution:** Fixed — both locations now describe the divergence; decision record requires `is_line_only()` gating before resolution.

### 3. [Low][Testing] Schema default weight was never asserted
- **Location:** `tests/DialogueSchemaTest.gd:135` (review-time); `resources/dialogue/greetings/greeting_generic.tres:15`
- **Evidence:** T9 checked `generic.weight == 1.0`, but the `.tres` pins `weight = 1.0`, so changing `@export var weight: float = 1.0` in `DialogueGreeting.gd` would not fail the test. No other case instantiated a greeting without setting `weight`.
- **Problem:** The documented schema default is unverified.
- **Recommendation:** Rename T9 to say "authored weight" and add a check on a fresh `DialogueGreeting.new()`.
- **Resolution:** Fixed — T9 renamed; T22 added for the schema default.

### 4. [Low][Testing] Interest field seeded with a trait-style id
- **Location:** `tests/DialogueSchemaTest.gd:56` (review-time)
- **Evidence:** `source.required_interests = PackedStringArray(["trait:likes_sports"])` while `required_traits` used `["trait:outgoing"]`.
- **Problem:** A copy/paste error makes a future field mislabel harder to spot in the round-trip assertion.
- **Recommendation:** Use an interest-style id.
- **Resolution:** Fixed — now `["interest:likes_sports"]`.

### 5. [Low][Testing] Fixture save results ignored
- **Location:** `tests/DialogueSchemaTest.gd:189,196` (review-time)
- **Evidence:** Two `ResourceSaver.save(...)` calls in `_make_mod_fixture()` discarded their `Error` returns.
- **Problem:** A failed fixture write surfaces later as a misleading "mod .tres registers into TYPE_GREETING/TYPE_RESPONSE" failure rather than a setup error.
- **Recommendation:** Check the return and `push_error` before continuing.
- **Resolution:** Fixed — both saves now guard with `!= OK` and abort fixture setup.

### 6. [Low][Testing] Pass marker lacked a completeness check
- **Location:** `tests/DialogueSchemaTest.gd:283-284` (review-time); `tests/run_dialogue_schema_tests.ps1:41`
- **Evidence:** `_finish()` printed `ALL_021_CHECKS_PASSED` whenever `_failed == 0`; the PowerShell runner treats that marker as authoritative. A truncated `_run()` would therefore pass.
- **Problem:** Silent omission of checks is indistinguishable from success.
- **Recommendation:** Assert the expected number of checks before printing the marker.
- **Resolution:** Fixed — `EXPECTED_CHECKS = 23` and T23 self-check added.

### 7. [Low][Testing] Misleading local variable name
- **Location:** `tests/DialogueSchemaTest.gd:126` (review-time)
- **Evidence:** `var authored_generic := ResourceLoader.load(RESPONSE_PATH)` loads `response:roundtrip`, not the authored generic sample; the assertion label says "round-trips as rollable" and the actual generic sample is line-only.
- **Problem:** The name suggests a different fixture than the one asserted.
- **Recommendation:** Rename to `round_trip_response`.
- **Resolution:** Fixed.

## Dropped claim (evidence audit)

- **"The sample response's roll fields are dead data because they differ from the keyed topic's."** — **REJECTED (MIXED).** Evidence showed `response_ask_day_success.tres:12-19` differs from `topic_ask_day.tres:16-22`, but the conclusion is unsupported: decisions explicitly give `DialogueResponse` its *own* roll fields and state it does not reference a separate topic (`idea-v2-decisions.md`, "Response contract"). Ticket 023 is meant to consume those response-owned fields via an extended resolver. Only the "reuse unchanged" wording (finding 1) was valid. No sample data was changed.

## Evidence Audit

### Claims
1. [SUPPORTED] "resolve() is statically typed to DialogueTopic and reads recipient_modifiers" — `scripts/DialogueResolver.gd:63,79`.
2. [SUPPORTED] "DialogueResponse has no recipient_modifiers and does not extend DialogueTopic" — `scripts/DialogueResponse.gd:1-2`, field list.
3. [SUPPORTED] "Empty checked_stat in DialogueTopic only removes the stat bonus" — `scripts/DialogueResolver.gd:102-140`.
4. [SUPPORTED] "T9 pinned the value in the .tres" — `resources/dialogue/greetings/greeting_generic.tres:15`.
5. [SUPPORTED] "Fixture saves ignored their Error returns" — review-time `tests/DialogueSchemaTest.gd:189,196`.
6. [SUPPORTED] "Marker depended only on the failure counter" — review-time `tests/DialogueSchemaTest.gd:283-284`.
7. [MIXED] "Sample response roll fields are dead data" — field difference shown; conclusion contradicted by the documented response contract.

### Verdict: PASS (after dropping the mixed claim)
- Unsupported/mixed claims: 1 (dropped).
- Action required: none outstanding; all supported findings were fixed and re-verified.

## Verification after fixes

- `tests/run_dialogue_schema_tests.ps1`: 23 passed / 0 failed, `DIALOGUE_021_OK`.
- v1 regressions re-run before the fixes: 018 41/41, 020 58/58, 019 60/60. The fixes touched only documentation, comments, and the 021 test harness, so the v1 results remain valid.
