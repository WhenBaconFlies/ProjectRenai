# Code Review: ticket 022 vs master

- **Branch:** ticket/021-dialogue-greeting-response-schemas (local commit `4d3e20a`, ticket 022 scope)
- **Base:** master (merge-base: `240e37fbda32755705901dfcb8ea9fceafc944ab`)
- **Scope note:** the branch also contains the 021 commits, which were already reviewed in `codereview-ticket-021-dialogue-greeting-response-schemas.md`. This report covers only the 022 commit (`git diff 8cf6be2..4d3e20a`: 71 files, 1903 insertions, 13 deletions).
- **Changed files:** 71
- **Findings:** 2 (Critical: 0, High: 0, Medium: 1, Low: 1)
- **Dropped claims:** 0

## Findings

### 1. [Medium][Architecture] No new rollable reply responses for the NPC-initiated flow

- **Location:** `resources/dialogue/responses/` (22 new response files); `resources/dialogue/responses/response_ask_day_success.tres:12`
- **Evidence:** `grep '^checked_stat = ' resources/dialogue/responses` over all 24 response files returns `checked_stat = ""` for 23 of them; the only non-empty value is `"charisma"` in `response_ask_day_success.tres:12`, which was authored by ticket 021. `scripts/DialogueResponse.gd:84-85` defines `is_line_only()` as `checked_stat.is_empty()`, so the 22 responses added by 022 are all line-only reactions with no roll and no deltas. `doc/idea-v2-decisions.md:59` requires the NPC-initiated player reply to be "a normal topic + roll using its own roll fields; its deltas are the final affection/mood change," and states reply options are selected by `topic_id` plus filters because outcome/band "do not exist at selection time." The one rollable response is keyed to `outcomes = ["success"]` and `relationship_bands = ["Friend", "Lover"]` (`response_ask_day_success.tres:13-14`), so it is not a wildcard reply option for `topic_id`-based selection.
- **Problem:** Ticket 023 will have no authored rollable reply for any topic except `topic:ask_day`, forcing it either to reuse one line for every NPC opening topic or to author new content outside the content ticket.
- **Recommendation:** Decide the reply contract in 023 first. If `DialogueResponse` keeps no trait/mood filter fields, add 2–3 rollable replies with `topic_id` set and `outcomes`/`relationship_bands` empty (e.g. `response:ask_day_reply`, `response:talk_sports_reply`, `response:compliment_reply`) with `checked_stat`, `difficulty`, and success/failure deltas authored, and extend the harness so it asserts at least one non-line-only response exists for several topics. If 023 instead adds explicit reply-filter fields to the schema, keep 022 unchanged and record that decision so a later content ticket owns the replies.
- **Resolution:** Fixed — added three rollable wildcard reply resources (`response:ask_day_reply` with `charisma` 5, `response:talk_sports_reply` with `dexterity` 5, `response:compliment_reply` with `charisma` 6; all keyed by `topic_id`, empty `outcomes`/`relationship_bands`, with success/failure deltas). `tests/TraitsAndDialogueContentTest.gd` T9 now requires a *line-only* default per topic so rollable replies cannot be mistaken for one, and new T22 asserts rollable reply options exist for at least three topics. Response total is now 27, dialogue total 55 (still within 40–60); decision record updated.

### 2. [Low][Testing] Harness rejects a zero point cost the schema allows

- **Location:** `tests/TraitsAndDialogueContentTest.gd:182`; `scripts/Trait.gd:25`
- **Evidence:** T7 fails a trait when `trait_resource.point_cost == 0`, while `Trait.gd:25` declares `@export var point_cost: int = 0`; zero is therefore a valid authored value. All 24 current traits happen to have non-zero costs, so the test passes today, but a legitimate free trait would make the content harness fail.
- **Problem:** The assertion enforces a policy the resource schema does not define.
- **Recommendation:** Drop the `point_cost == 0` condition (keep the non-empty tags check) and rename the T7 label to match, or document in `doc/idea-v2-decisions.md` that 022 intentionally requires non-zero trait costs.
- **Resolution:** Fixed — `_traits_well_formed()` no longer rejects `point_cost == 0`; it keeps the non-empty tags check and documents that `Trait.gd:25` permits zero. T7's label was updated to match.

## Evidence audit

- Claim 1: **SUPPORTED** — grep output over all 24 response `.tres` files (23 empty / 1 `"charisma"`), `DialogueResponse.gd:84-85`, `doc/idea-v2-decisions.md:59`, `response_ask_day_success.tres:12-14`.
- Claim 2: **SUPPORTED** — `tests/TraitsAndDialogueContentTest.gd:182`, `scripts/Trait.gd:25`.
- Verdict: **PASS** — both claims cite file:line and command output; no vague or unsupported claims retained.

## Verification record (not findings)

- `tests/run_traits_and_dialogue_tests.ps1`: `passed=23 failed=0`, `ALL_022_CHECKS_PASSED`, `TRAITS_DIALOGUE_022_OK`.
- `tests/run_dialogue_schema_tests.ps1` (021 regression): `passed=23 failed=0`, `DIALOGUE_021_OK`.
- `tests/run_integration.ps1` (v1 day loop, ticket 018): `passed=41 failed=0`, `INTEGRATION_018_OK`.
- `tests/run_chunk_tests_019.ps1`: `60 passed, 0 failed`, `CHUNKMANAGER_019_OK`.
- `tests/run_chunk_tests.ps1` (ticket 020): `58 passed, 0 failed`, `CHUNK_020_OK`.
