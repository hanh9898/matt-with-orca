# Troubleshooting a wave

Each entry: the observable symptom, then how to handle it. When an incident exposes a trap the next wave's workers would also hit, copy that trap into the "Traps already hit" section of the next wave's common rules.

Only positive evidence authorizes stopping, abandoning or retrying a worker: liveness `exited`, or a transcript whose last turn sent no `worker_done`. Liveness `unverifiable`, output that stands still, or a long wait are all **absence**: keep waiting or inspect further (`worker-show`, `worker-read --dispatch <id> --source auto`). The exact command for each state: `orca skills get orchestration --reference references/recovery-and-cleanup.md`.

## Workers

**`worker-start` exits non-zero.** The receipt is the only recovery source: read its `state`, `stage`, `failedStage`, `residualResources` and recovery commands, and run exactly those. Re-running the original command creates a second worktree and a second Task. A worker that failed before `ready` still owns the terminal it created: release it with `worker-release`, never by closing the terminal by hand.

**`worker-start` returns `state: outcome_unknown`, `stage: turn_start_unobserved`.** Orca typed the preamble and spec into the agent but saw no first turn start within 30 seconds. The recorded case: the Enter keystroke was swallowed, and the spec sat in the agent's input box as a draft. The terminal handle is in the receipt's `effects` (`kind: terminal`, `role: agent`). In order:

1. `worker-list --run <run id> --json`: that row's `projection.liveness.verdict` must be `live`. Anything else: follow `projection.nextAction`.
2. `orca terminal read --terminal <handle> --screen`: if the `draft` field holds the preamble and `=== TASK ===`, submit exactly that draft with a single Enter and no text: `orca terminal send --terminal <handle> --enter --json`.
3. Read the screen again after about 20 seconds: an empty `draft` and an agent running a turn (a tool-call line, or `Actioning…`) means the worker took the task; treat it as `ready` from here. That Enter makes Orca mark the terminal `user_takeover`: `worker-release` in step 5 then returns `state: retained`, `processAction: none`, and leaves the terminal alive. Write "terminal user_takeover <handle>" in the private resources column, so step 8 closes that terminal.
4. An empty `draft` with the agent sitting at an empty input box and no turn: the input is lost. `worker-stop --dispatch <dispatch id>`, then `worker-start --task <task id> --retry-of <dispatch id> --worktree id:<worktree id> --agent <agent>` with the same spec, and write the new dispatch id into the log.

**Worker stops midway** (session limit, API error, context exhausted), with positive evidence. Check its branch and directory for what is really done. If the remainder is small, do it yourself. If it is large, wait for the limit to reset, then run again in the **same worktree**: `worker-start --task <task id> --retry-of <dispatch id> --worktree id:<worktree id> --agent <agent>`. The new spec states which part is done and who did it, narrows the task to exactly the unfinished part, and restates the common rules. Write the new dispatch id into the log. After three consecutive failures of one Task, Orca marks that Task `failed`: stop and tell the user.

**`worker_done` with `--outcome failed`.** Read the summary and the ticket's comments. If the cause is within the worker's reach (missing information, a misread ticket), add to the common rules or the ticket and run again as above. If the cause needs a human decision, record it in the ticket and set `ready-for-human`.

**Report is correct but incomplete.** A claim like "clean" or "passing" only covers what the worker checked. Open the real artifact (screenshot, page, command output) and check the aspects the report does not mention.

**Branch name differs from worktree name.** Orca names the branch from `--name` and may add a prefix or change characters. Get the branch name with `git -C <worktree> branch --show-current`.

**Terminal handle stale** after Orca restarts. Keep going by dispatch id; get the new handle from `worker-show`.

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
