---
name: matt-with-orca
description: Locate where the work stands (setup, grill, spec, tickets, or an agent wave), suggest the next step, and orchestrate tickets in waves of supervised Orca workers.
disable-model-invocation: true
---

# Orchestrate tickets in waves with Orca

You are the coordinator. Every run starts by **locating**: where the work stands and what the next step is. Once tickets exist, each ticket is worked by one Orca worker in its own worktree; you split tickets into **waves**, write the **common rules**, spawn, check reports, merge into the **integration branch**, review where the tickets touch, then open the next wave.

**Input:** $ARGUMENTS (a feature name, a ticket folder, or empty)

Three words used throughout:

- **Wave**: a set of tickets run in parallel. A ticket joins a wave once every ticket it depends on is `resolved` and merged. Each wave is one Orca orchestration **Run**.
- **Integration branch**: the branch collecting the results of every wave. Each wave branches its worktrees off a **base commit** pinned on this branch.
- **Done**: the state a worker must reach before it sends `worker_done`, defined in the common rules (step 3).

Orca's words: a ticket is a **Task**, one attempt at a Task is a **Dispatch**. Every action on a worker goes by dispatch id, never by terminal handle or title.

**Waiting commands run in the background.** A coordinator juggles several workers at once, and a foreground wait freezes all of them: no question answered, no report checked, no merge, until it returns. So every command that waits runs in the shell's background mode (Claude Code: `run_in_background: true`): `scripts/spawn-worker.sh` (about a minute each), `check --wait` (minutes), `orca skills install`. Start it, keep coordinating, and read its output file when the harness says it finished. Quick reads (`worker-list`, `worker-show`, `terminal read`, `git`) run in the foreground.

## 0. Locate the state and suggest the next step

Read the signals below on the real repo. Walk the table from the bottom row up; the first row that matches is the current stage.

| Stage | Observable signal | Next step |
|---|---|---|
| A. Not configured | No `docs/agents/issue-tracker.md`, and `CLAUDE.md`/`AGENTS.md` has no `## Agent skills` section | The user types `/mattpocock-skills:setup-matt-pocock-skills` |
| B. Idea not sharp | No spec for the feature; the feature's terms are not in `CONTEXT.md` | `/mattpocock-skills:grill-with-docs`. Work too large for one session with no visible path: `/mattpocock-skills:wayfinder`. A raw issue someone else filed: `/mattpocock-skills:triage` |
| C. Grilled, no spec | `CONTEXT.md` or an ADR records the feature's decisions; no spec file yet | Ask the user whether `/mattpocock-skills:prototype` is needed, then `/mattpocock-skills:to-spec`; both run in the **same session** that did the grilling. See the stage C notes below the table |
| D. Spec, no tickets | A spec exists (location per `issue-tracker.md`); the feature's `issues/` folder is empty or missing | `/mattpocock-skills:to-tickets <spec path>`, run in the same session that wrote the spec |
| E. Tickets, no wave run yet | Tickets exist; no `wave*-common-rules.md` file | A single ticket, or a pure chain where no two tickets can ever run side by side: `/mattpocock-skills:implement` in this session. Any width at all: step 1 of this skill |
| F. Wave in progress | A `wave<N>-common-rules.md` file exists, and a ticket of that wave (listed in the file's title) is not yet `resolved`/`ready-for-human`; or the file has `## Wave workers` but no `## Review`, or the "cleaned" column is not fully checked | Resume at the missing step, see right below the table |
| G. No work left for agents | At least one ticket exists, and every ticket is `resolved` or `ready-for-human` | Summarize per step 8; list the work waiting on humans |

Ticket status is the primary signal for stage F; the two log sections `## Wave workers` and `## Review` only tell you which step is missing. A wave file with no `## Wave workers` whose tickets are all done is an old, finished wave, not stage F.

For stage F, bind this session to the wave's Run: `orca orchestration run-use --id <run id from the log> --json`. A previous session may have ended mid-command (a crash, a killed background job), so run the **recovery sweep** before anything else, and report what it finds before resuming any step:

- `git worktree list` and `orca terminal list --json` against the log table: a worktree or agent terminal of this wave with no row is an orphan of an interrupted spawn; a row whose worktree is gone is a cleanup already done.
- Every row with a request id but no dispatch id: `orca orchestration request-show --request <request id> --json`. `completed` means the Dispatch exists: read it from the recorded receipt and fill the row. `pending` means replay that exact spawn with the same request id. `absent` proves nothing: inspect the worktree and its terminals first.
- Every background job the previous session started (spawn, wait): its output file, if any, holds a `RESULT` line or a Delivery that was never processed.

Then `orca orchestration worker-list --run <run id> --json`, and take each unfinished ticket by the dispatch id in the log:

- No dispatch: step 4, spawning only for that ticket.
- Liveness `live` or `unverifiable`: wait with the step 5 loop.
- An accepted `worker_done` while the ticket is unfinished, or liveness `exited` without a `worker_done`: handle it per "Worker stops midway" in [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md). This ticket's branch is not merged yet.

Once every ticket of the wave is done: a ticket branch still unmerged (`git branch --no-merged <integration branch>`) goes to step 5, reading its report from the ticket's comments, then step 6; no `## Review` yet goes to step 7; an uncleaned row goes to step 8.

Stage C always presents the user with two options and waits for their choice, even when one option clearly fits better:

- **Prototype first**: a design question remains that grilling could not settle in words (is the state model or logic right, what should the UI look like). Run `/mattpocock-skills:prototype` first, record the conclusion in `CONTEXT.md` or an ADR, then `/mattpocock-skills:to-spec`.
- **Straight to spec**: every design decision is settled. Run `/mattpocock-skills:to-spec` directly.

Name any open design question you see in the grilling results, or state that you see none.

Two notes for stages C and D: `to-spec` and `to-tickets` synthesize from the current conversation, so they must run in the session that still holds the grilling results. If that session is gone, tell the user, and suggest a short re-grill over the existing docs before writing the spec. The skills in stages A to D are typed by the user only; this skill only suggests the command.

Present three things to the user: the current stage, the signals you saw with their paths, and **one** concrete next step (a command to type, or a step number of this skill); stage C gets the two options above instead. Wait for the user to agree.

**Done when**: the user has confirmed the stage and the next step. If the next step lies outside this skill, stop here.

## 1. Prepare

The Orca toolchain has two parts. The **install** part changes only when Orca is upgraded, so it carries a **stamp**: the file `.installed-version` in this skill's directory, holding the exact `orca --version` line of the last passing check. The **session** part is checked on every run.

Install:

- `orca --version` runs. If its output equals the content of `.installed-version`, the install part passes; go to the session part.
- Different, or no `.installed-version` yet: `orca skills installed` lists `orca-cli`, `orchestration`, and `tdd`, `diagnosing-bugs`, `code-review` from the `mattpocock-skills` plugin (the output is long; filter it with `grep`). On a pass, write the `orca --version` line into `.installed-version`.

Session:

- The runtime is up: `orca status --json` has `result.runtime.reachable: true`.
- This session runs in an Orca-managed terminal, because a Run binds to the coordinator's terminal: `orca worktree current --json` returns the repo's worktree. Keep `result.worktree.repoId` for the repo selector.
- Guides: `orca skills get orchestration` and `orca skills get orca-cli`; read both. Flags and subcommands change between Orca releases, so the commands in this skill are a frame; the exact flags come from those two guides and `--help`.

If any item fails, delete `.installed-version`, install per [`SETUP.md`](SETUP.md), then check that item again.

The worker agent id (`claude`, `codex`, ...) comes from the `orca-cli` guide; pass `--model` only when the user names one.

Identify the tracker from `docs/agents/issue-tracker.md`. Identify the integration branch with `git branch --show-current`, never from the directory name. The repo selector is `id:<repoId>`, with `repoId` taken from `orca worktree current --json` above.

**Done when**: the install part passes (by stamp or by a fresh check), the three session items pass, and you have stated five things: the ticket folder, how status and dependencies are recorded, the integration branch, the repo selector, and the agent (plus model, if the user named one) the workers will use.

## 2. Build the graph and split into waves

**Width** is the point of this skill: every wave takes every ticket that can run now, and the coordinator works to make that set wider. A ticket can run now when every ticket in its `Blocked by` is merged and its status is `ready-for-agent`.

Read every ticket: status, dependency line (`Blocked by`), comments. Draw the dependency graph on one line, marking each ticket's status, for example `01✓ → {02, 03?} → {04, 05, 06} → 09`.

Two tickets in the same wave must be logically independent. If they touch the same registration file (manifest, package index, route table, permission file) they can still share a wave, but the common rules must assign each ticket its own file zone.

Run each symptom ticket's own reproduction on the base commit. A symptom that does not reproduce, or an acceptance criterion that already passes, leaves a worker nothing to fix but something to invent: take that ticket out of the wave and back to triage (the answer may be a ticket rewritten as a test that locks the correct behaviour).

Then hunt for lost width, and list every case with the one thing that would recover it:

- **A ticket waiting on a human** (`needs-triage`, `ready-for-human`) that would join this wave, or that blocks tickets which would: name the exact question the human must answer, or the decision they must make.
- **A false edge**: a `Blocked by` that stands for a shared file rather than a logical dependency (the later ticket neither calls nor reads what the earlier one builds). Propose dropping the edge and giving both tickets a file zone; the edge changes only in the ticket, and only with the user's agreement.

This skill holds the dependencies between waves; keep them out of Orca's `--deps`: an Orca Task `completed` does not mean its branch is merged.

Present the graph, the upcoming wave, and the lost-width list to the user, and wait for approval. A wave of one ticket is a signal to resolve the lost-width list first when the user can.

**Done when**: every open ticket has a wave number, every case of lost width has been named to the user with its unblocking question, and the user has approved the upcoming wave.

## 3. Write the wave's common rules

Pin the base commit: `git rev-parse <integration branch>`. Write `wave<N>-common-rules.md` next to the ticket folder, following [`COMMON-RULES-TEMPLATE.md`](COMMON-RULES-TEMPLATE.md); its first section is the graph from step 2, with each ticket's wave and status, so the dependency tree lives on disk.

The common rules are the single place holding what every worker in the wave needs to know, so each worker's own spec carries only three things: which ticket, which private resources, and which flow (step 4). The file is also the wave's log: steps 4 and 7 append to it, so step 0 of a later session can read where an unfinished wave stands.

**Done when**: every section of the template has content or reads "not applicable", and every trap found in earlier waves is copied into the traps section.

## 4. Spawn

Create the wave's Run: `orca orchestration run-create --objective "Wave <N>: tickets <NN>, <NN>" --json`. Write the `## Wave workers` heading, a `Run: <run id>` line, and the table header row (ticket, task id, dispatch id, worktree id, branch, base commit, private resources, cleaned) at the end of the common rules file **before** spawning the first worker. Write each worker's row as soon as it is spawned, so any session reopened midway can read which workers exist.

Spawn in two moves, so the agent is **warm** (its input box drawn and taking keys) before the spec reaches it. A single `worker-start --worktree new-top-level --agent` types the spec into an agent that is still booting: the text lands, the Enter is lost, and the receipt reads `outcome_unknown` / `turn_start_unobserved` with the spec left as a draft (5 of 6 cold starts on Orca 1.4.210). [`scripts/spawn-worker.sh`](scripts/spawn-worker.sh) does both moves: `worktree create --agent`, a poll of the screen until the agent's input box is drawn (`terminal wait --for tui-idle` can fire before anything is drawn, so it is not the warm signal), then `worker-start --terminal`, repeated while Orca answers `agent_unconfigured` (no Task is created then). The script runs every Orca mutation (`worktree create`, `worker-start`) under one lock shared by all spawn jobs, because parallel mutations have failed in three ways (a `worktree create` that answered `runtime_unavailable` for a worktree it created, a missing `startupTerminal`, a hang); the warm-ups still run side by side. The lock narrows these failures without ending them: a lone `worktree create` has also answered `runtime_unavailable` after creating the worktree, which the script reports as `existing` instead of retrying. Each `worker-start` carries a `--retry-request` id, so a hung or lost answer can be asked about with `request-show` instead of guessed at. Write each ticket's spec to a file, then start one background job per ticket, the whole wave at once:

```text
bash <skill dir>/scripts/spawn-worker.sh --new --repo <repo selector> --name wave<N>-<NN>-<slug> \
  --base <integration branch> --agent <agent> --display-name "[Wave N] <NN> <ticket name>" \
  --title "[Wave N] <NN> <ticket name>" --spec-file <spec file>
```

The script's `--warm` text defaults to `bypass permissions`, the status line of Claude Code as Orca launches it; another agent needs its own warm text.

Each job ends on a `RESULT` line with the worktree id, handle, request id, task id, dispatch id, `state`, `stage` and error; write the log row from it right away, with the handle and request id in the private resources column. The worker is started when `state` is `ready`. Anything else, including `outcome_unknown` with a warm spawn (2 of 12 warm spawns on Orca 1.4.210, both with the spec already submitted and the agent working), and any `error`: act per [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md). Get the branch name with `git -C <path> branch --show-current`, and check that `git -C <path> rev-parse HEAD` equals the base commit; if the integration branch stays still while you spawn, every worktree in the wave shares one base. Orca may place the worktree **nested** inside the integration branch's checkout (`<checkout>/<--name>`); when it does, add `wave*-*/` to that checkout's `.git/info/exclude`, so `git status` and `git add` there see only the integration branch's files.

`<spec>` holds exactly four things: the **absolute** path to the common rules in the integration branch's checkout (the file is the wave's live log and is not in the worktree), the path to the ticket, the private resources (database name, port, volume, temp directory; a distinct set per worker), and the **flow**. Orca injects the lifecycle preamble (task id, dispatch id, the `ask` command, `worker_done`) ahead of the spec; the spec does not repeat it.

The **flow** is the chain of skills the worker runs for that ticket. Read the ticket, then pick one row:

| The ticket describes | Flow |
|---|---|
| A symptom: broken, erroring, wrong numbers, slow | `/mattpocock-skills:diagnosing-bugs` then `/mattpocock-skills:tdd` |
| Behaviour that should exist | `/mattpocock-skills:tdd` |
| `Status: ready-for-human` | spawn no worker |

Every flow ends the way Matt's `/implement` does: `/mattpocock-skills:code-review` with the ticket's base commit (its row's) as the fixed point, fix the findings (the refactor phase `tdd` hands to review lives here), then make the last commit and send `worker_done`. `code-review` opens fresh-context sub-agents for its two axes, so the reviewer stays independent of the worker. A finding that needs a human decision goes through `ask`.

Symptom tickets go through `diagnosing-bugs` because that skill forces the worker to build a **tight** pass/fail loop that goes **red** on exactly that symptom, so the fix is proven to hit the right place instead of merely making the symptom disappear.

Chaining another Matt Pocock skill means adding a row to this table, not a prose branch. Point only at **model-invocable** skills: `tdd`, `code-review`, `diagnosing-bugs`, `prototype`, `research`, `domain-modeling`, `codebase-design`, `resolving-merge-conflicts`, `wizard`. The rest (`implement`, `to-spec`, `to-tickets`, `grill-with-docs`, `triage`, `wayfinder`) carry the `disable-model-invocation` flag; only a human can type them, so a worker cannot run them.

If the wave's first worker reports it cannot find a skill, the plugin has not reached the worktree: paste the method straight into the specs of the remaining workers, record it in the traps section of the common rules, and delete `.installed-version` so the next run checks the install part again.

**Done when**: every ticket in the wave has exactly one `ready` dispatch and one row in the table.

## 5. Wait and check each report

The wait loop, run until every dispatch of the wave has settled:

```text
orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms 540000 --json
```

Run it in the background, and keep `--timeout-ms` below the shell's per-command limit (Claude Code's Bash: 600000 ms). A coordinator terminal is bound to one Run at a time, so any other `run-create` or `run-use` from it, a second wave or a diagnostic experiment alike, fences the wave's loop (`consumer_fenced`). The coordinator terminal holds only the current wave's Run; experiments run from another Orca terminal.

**Steer a running worker** instead of waiting for its report: a decision the user makes mid-wave, an answer that changes the ticket, or a trap another worker just hit goes to that worker with `orca orchestration send --to dispatch:<dispatch id> --subject "<subject>" --body "<decision>" --json`. The common rules tell workers to read their follow-ups at each checkpoint and right before `worker_done`, so the change lands inside the current attempt rather than in a second worker.

**Liveness of the agent** comes from `worker-list --run <run id> --json`, the row's `projection.liveness`. `worker-show`'s `observation.status` is the terminal's liveness only: a `live` terminal can hold a dead or stuck agent.

Process every message in the batch before passing `--ack <delivery id>` on the next `check`: answer `question` and `escalation` with `orca orchestration reply --id <message id> --body "<answer>"`; ask the user first when the answer is theirs to give. A `heartbeat` only proves liveness: ack it, nothing else. A timeout or an empty result is a checkpoint, not a failure. After three empty waits in a row, run `worker-list --run <run id> --json` and follow each row's `projection.nextAction`.

For each `worker_done`, match the dispatch id against the log, then check the real artifacts, not the report's words:

- `--outcome` is `succeeded`; `failed` goes to [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md);
- the commits sit on the ticket's own branch (`git log <branch>`);
- the ticket's status has changed, and its comments carry verification evidence;
- the report's most decisive claim is re-run once by you (call the endpoint, open the screen, look at the screenshot);
- the ticket's comments carry the `code-review` result: the number of findings per axis and the outcome of each. Missing means the worker did not finish its flow;
- symptom tickets: the report shows the loop **red before** the fix and green after. Green alone does not tell you whether the fix hit the right place or only masked the symptom;
- private resources are cleaned up, or kept for a stated reason.

Once checked, decide the settled worker's **next owner** before the ack:

- **Reuse** when the same ticket has immediate follow-up work (a check above failed, a decision that changes the code, a gap the report names): create the follow-up Task with `orca orchestration task-create --spec "<follow-up>" --json`, then hand it to the same agent with `worker-start --task <new task id> --terminal <handle> --worktree id:<worktree id> --retry-request <new id> --json`. The worker keeps its context, and no new spawn is needed. Write the new task and dispatch ids into the ticket's row.
- **Release** otherwise: `orca orchestration worker-release --dispatch <dispatch id> --json`. Release archives the worker's output (readable again with `worker-read`); the worktree and branch stay for steps 6 and 7. The terminal came from `worktree create`, not from `worker-start`, so release keeps it (`state: retained`, `reason: external_terminal`). This is the one place this skill closes a terminal by hand, and only after release has answered `external_terminal` for a dispatch `worker-show` reports settled: `orca terminal close --terminal <handle> --json`. Any other retained state (`release_pending`, `release_unknown`, `user_takeover`) follows [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

Worker stopped midway or report incomplete: see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

**Done when**: every dispatch of the wave has settled, every report is checked or recorded as failed with a reason, and `worker-list --run <run id> --terminal-state reclaimable --json` is empty.

## 6. Merge into the integration branch

Merge each ticket as soon as its report passes step 5, while the rest of the wave keeps running: steps 5 and 6 interleave. One merge commit per ticket: `git merge --no-ff <ticket branch> -m "Merge ticket NN (<name>) into <integration branch>"`. After each merge, run the cheapest verification the repo has (install, build, lint, test). With nested worktrees, verify only the files git tracks on the integration branch, because commands that scan the tree (test runners, `**` globs) also run the unmerged code of the worktrees still open.

**Rolling start.** After each green merge, re-read the graph: a ticket whose `Blocked by` is now fully merged and whose status is `ready-for-agent` joins the current wave at once, without waiting for the rest of it. Spawn it per step 4 into the current Run, with the integration branch's new head as its base commit, written in its row and named in its spec; append it to the wave file's title and graph. Its worker's `code-review` uses that base commit.

Conflict, failure after a merge, or a test count after the merge that does not match the test files git tracks: see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

**Done when**: every ticket in the wave is merged, every ticket its merges unblocked has been started in the wave, and verification is green after the last merge.

## 7. Review where the tickets touch, fix, close

Each ticket was already reviewed by its worker in step 4. This pass targets only what a per-ticket review cannot see: the **seams** between tickets once merged (registration files, shared interfaces, two tickets solving the same thing two ways).

- A one-ticket wave has no seam: write `## Review` as "not applicable: one-ticket wave, reviewed by its worker", then go to step 8.
- A wave of two or more tickets: run `mattpocock-skills:code-review` with the wave's first base commit (step 3) as the fixed point, so tickets started by rolling start are covered too, stating in the call that each ticket was already reviewed on its own and only seam findings should be reported. Present the Standards and Spec axes separately.

Fix each finding. A finding contained in one ticket's zone goes to a new worker in that ticket's own worktree: `bash <skill dir>/scripts/spawn-worker.sh --worktree <worktree id> --launch "<agent launch command>" --title <title> --spec-file <spec file>`, in the background. The launch command is the one Orca's launcher ran, the line after the shell prompt at the top of the ticket's first terminal (e.g. `claude --dangerously-skip-permissions`). An agent started this way is not tracked by Orca's launcher, so the receipt reads `turnStart: unsupported`: confirm with `terminal read --screen` that the agent is running a turn and no `draft` remains. Then wait, check and merge again as in steps 5–6. The previous worker was released in step 5 (step 5 reuses it only for follow-up known at that point), so the new one starts with a blank context: its spec holds the path to the common rules, the ticket, the ticket's comments (the previous worker's report), the files the previous worker touched, and the finding. A finding cutting across several tickets you fix yourself on the integration branch. Gather every question that needs a human decision into one round, present it, then record the decisions in the comments of the tickets involved, so the next wave can read them.

Append a `## Review` section to the end of the common rules file: the fixed point, the number of findings per axis, and the outcome of each finding.

**Done when**: every finding has an outcome (fixed, skipped with a reason, or waiting on a human), every decision is recorded in a ticket, and the `## Review` section is written.

## 8. Clean up the wave, open the next

`orca worktree rm` deletes the worktree directory, so for each row in the `## Wave workers` table, check three things first:

- `worker-show --dispatch <dispatch id>` shows the dispatch has settled, and `orca terminal list --worktree id:<worktree id> --json` shows no agent terminal of that dispatch left open;
- `git -C <worktree> status --porcelain` is empty;
- the ticket's branch appears in `git branch --merged <integration branch>`.

With all three, `orca worktree rm --worktree id:<worktree id> --json` (it also deletes the local branch when Orca can prove the branch is merged), clean up the non-Orca resources listed in the private resources column, then check the "cleaned" column. If any is missing, leave the row as is and see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

Return to step 2 with the new base commit; the next wave creates a new Run in step 4. When no open ticket can join a wave, report a summary: which tickets are `resolved`, which wait on a human, and which remain open and what blocks them.

**Done when**: every row in the table is checked as cleaned or has a reason for keeping it that the user has been told, and the next wave is open or the summary is reported.
