# Troubleshooting a wave

Each entry: the observable symptom, then how to handle it. When an incident exposes a trap the next wave's workers would also hit, copy that trap into the "Traps already hit" section of the next wave's common rules.

Only positive evidence authorizes stopping, abandoning or retrying a worker: liveness `exited`, or a transcript whose last turn sent no `worker_done`. Liveness `unverifiable`, output that stands still, or a long wait are all **absence**: keep waiting or inspect further (`worker-show`, `worker-read --dispatch <id> --source auto`). The exact command for each state: `orca skills get orchestration --reference references/recovery-and-cleanup.md`.

## Workers

**`worker-start` exits non-zero.** The receipt is the only recovery source: read its `state`, `stage`, `failedStage`, `residualResources` and recovery commands, and run exactly those. Re-running the original command creates a second worktree and a second Task. A worker that failed before `ready` still owns the terminal it created: release it with `worker-release`, never by closing the terminal by hand.

**`worker-start` returns `state: outcome_unknown`, `stage: turn_start_unobserved`.** Orca typed the preamble and spec into the agent but saw no first turn start within 30 seconds. Orca's own rule for `outcome_unknown` is to inspect, then choose `worker-stop` or `worker-abandon`; this entry adds one path of its own (form B), used only on the positive evidence it names. The terminal handle is in the `RESULT` line (or the receipt's `effects`, `kind: terminal`, `role: agent`). First, `worker-list --run <run id> --json`: that row's `projection.liveness.verdict` must be `live`; anything else, follow `projection.nextAction`. Then read the screen, `orca terminal read --terminal <handle> --screen --json`, and match one form:

- **A. The spec is stuck**: the `draft` field holds the preamble and `=== TASK ===`. Cause, as diagnosed: the agent was still booting, so the text landed and the Enter was lost. Mostly a cold spawn, which the warm spawn of step 4 prevents. Submit exactly that draft through Orca's submit observer: `orca terminal send --terminal <handle> --enter --wait-submit 30 --json`. It never resends; on timeout it returns the input-accepted receipt. Then continue as in form B.
- **B. The spec went in, the start was not seen**: `draft` is empty and the agent is running a turn (a tool-call line, a spinner such as `Actioning…`). Seen twice in 12 warm spawns; both workers settled with a normal `worker_done`. Treat the dispatch as `ready` only once **two** positive signs hold: that screen, and a first `heartbeat` (or any lifecycle message) from this exact dispatch id in the next `check`. Write "outcome_unknown, accepted on screen + heartbeat" in the log row. Until the heartbeat arrives the dispatch stays unknown: keep waiting, stop or retry nothing.
- **C. The input is lost**: `draft` is empty and the agent sits at an empty input box with no turn. `worker-stop --dispatch <dispatch id>`, then run the Task again warm (see "Running a Task again" below).

A raw `terminal send --enter` without `--wait-submit` makes Orca mark the terminal `user_takeover`; `worker-release` then leaves it alive (see "Terminal retained as `user_takeover`" under Cleaning up).

**`worker-start` hung or its answer was lost** (`RESULT` with `error=worker_start_timeout`, a crashed session, a killed background job). The script already asked `request-show` for the request id it used; the `RESULT` line carries `request_state`. `completed`: the mutation took effect, so read the Task and Dispatch with `orca orchestration request-show --request <request id> --json` and write the row. `pending`: the mutation is still running or Orca restarted before recording it; replay the same `worker-start` with `--retry-request <request id>`, which joins it instead of starting a second one. `absent`: this runtime holds no receipt under this caller, which is not proof that nothing happened; inspect `worker-list --run <run id>` and the worktree's terminals before starting anything.

**`worktree create` failed or hung** (`RESULT` with `error=worktree_create_failed`). The worktree may exist anyway: the `RESULT` line's `existing` field names a checkout at that name, and `raw` points at Orca's full answer. With an existing worktree and no agent terminal, run the spawn again in existing mode on that worktree (`--worktree <repoId::path> --launch "<agent command>"`) rather than creating a second one. With no worktree, run the same `--new` spawn again. A timeout (`rc=124`) under load: wait for `orca status --json` to answer promptly before trying again.

**Running a Task again.** Two shapes, both in the **same worktree** and both through `bash <skill dir>/scripts/spawn-worker.sh --worktree <worktree id> --launch "<agent launch command>"` in the background:

- Same spec: add `--task <task id> --retry-of <dispatch id>`. The retry reuses the spec stored on the Task; `--task` and `--spec` are mutually exclusive, so a retry cannot carry new instructions.
- New instructions (a narrowed task, a correction): add `--title <title> --spec-file <spec file>`. This creates a new Task; write both the old and the new dispatch id into the log row.

After three consecutive failures of one Task, Orca marks that Task `failed`: stop and tell the user.

**Worker stops midway** (session limit, API error, context exhausted), with positive evidence. Check its branch and directory for what is really done. If the remainder is small, do it yourself. If it is large, wait for the limit to reset, then run it again with new instructions: the spec states which part is done and who did it, narrows the task to exactly the unfinished part, and restates the path to the common rules.

**Orca restarted mid-wave** (`_meta.runtimeId` in any receipt differs from the one before). Liveness turns `unverifiable` with `stale_status` or `missing_status`: that is absence, not death. Keep going by dispatch id; handles that still resolve stay valid, and `worker-show` names the current one. Positive evidence of death is the worker's screen showing a bare shell prompt with no agent UI, no `worker_done`, and no new commit on the branch: then `worker-stop` and run the Task again.

**`worker-start` or `check` answers `consumer_fenced`.** This coordinator terminal is bound to a different Run than the one the command targets; a terminal holds one Run at a time. It happens when an experiment or a second wave ran `run-create` or `run-use` from the coordinator terminal. Bind back with `run-use --id <run id>`, and move the experiment to another Orca terminal.

**`worker_done` with `--outcome failed`.** Read the summary and the ticket's comments. If the cause is within the worker's reach (missing information, a misread ticket), add to the common rules or the ticket and run the Task again (same spec, since the fix lives in the files it points to). If the cause needs a human decision, record it in the ticket and set `ready-for-human`.

**Report is correct but incomplete.** A claim like "clean" or "passing" only covers what the worker checked. Open the real artifact (screenshot, page, command output) and check the aspects the report does not mention.

**Branch name differs from worktree name.** Orca names the branch from `--name` and may add a prefix or change characters. Get the branch name with `git -C <worktree> branch --show-current`.


## Merging

**Verification green because of nested worktrees.** Orca worktrees sit inside the integration branch's checkout, and the verification command scans the tree: the test count after a merge exceeds what the test files git tracks contain, or tests of an unmerged ticket run too. Restrict the input to files git tracks, for example with `node --test`: `git ls-files '*.test.js' | xargs node --test`. Check: the printed test count matches the tests in those files. Passing a directory name straight to the runner does not always work (`node --test test/` on Node 24 fails with `Cannot find module`).

**Conflict in a registration file**, caused by two tickets both adding lines to a manifest, package index, route table, or permission file. Keep both sides' lines, in ticket-number order.

**Install is green but the real run fails.** For example, two controllers in one addon register a helper under the same name and one silently shadows the other: installing reports nothing, only a real HTTP call fails. Fix it, then add the real-call check to the "Done means" section and to the traps section of the next wave's common rules.

**Moving the result onto another branch** (for example a test branch that has drifted far from the main one). Create a new branch from the target, cherry-pick exactly the reviewed commits, then compare trees: `git diff <reviewed commit> <replayed commit> -- <feature paths>` must be empty. An automatic replay can duplicate lines in registration files; the tree comparison catches this.

## Cleaning up

**Worktree has uncommitted changes.** Keep the worktree: `orca worktree rm` would delete the directory along with those changes. Look at `git -C <worktree> diff`; changes that belong to the ticket go to a new worker in that worktree to commit; temporary junk is reported to the user before being discarded.

**Ticket branch not merged.** Go back to steps 5 and 6 for that ticket; clean up only after the merge.

**Dispatch not settled.** Wait for it to settle. To interrupt, ask the user first, then `worker-stop --dispatch <id>`; this only closes the agent terminal and never deletes the worktree.

**Terminal retained as `user_takeover`** (see `outcome_unknown` above). The dispatch has settled, but release left the terminal alive, so the first cleanup check fails on "terminal released". Once the other two checks pass, close that exact terminal with `orca terminal close --terminal <handle>`, confirm with `orca terminal list --worktree id:<worktree id> --json`, then continue with `orca worktree rm`.

**Release reports `release_pending` or `release_unknown`.** Run exactly the recovery command in the receipt; closing the terminal by hand does not replace a release.

## Environment

**Remote unreachable** (SSH timeout, HTTPS blocked). Keep the commits local, tell the user, and check again when they report the network is back. Push and open a merge request only after `git ls-remote` succeeds.
