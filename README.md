# matt-with-orca

A simple multi-agent orchestrator for Claude Code. It combines [Matt Pocock's skills](https://github.com/mattpocock/skills) (grill, spec, tickets, TDD, code review) with [Orca](https://github.com/stablyai/orca)'s orchestration layer, which runs supervised coding agents in their own worktrees.

You write the tickets with Matt's skills. `matt-with-orca` runs them in **waves**: every ticket gets its own Orca worker in its own git worktree, and the coordinator checks, merges, reviews, and cleans up before starting the next wave.

It is the Orca sibling of [matt-with-paseo](https://github.com/hanh9898/matt-with-paseo): the same eight-step loop, rebuilt on Orca's Runs, Tasks and Dispatches.

## Why

Matt Pocock's skills take a feature from a vague idea to a set of small, dependency-ordered tickets. Running those tickets is still sequential by default: `/implement` works through them one at a time in a single session.

Orca can run many supervised workers in parallel, each in its own worktree, and records who owns which attempt and when it has settled. What it does not know is which tickets are safe to run together, what each worker needs to be told, or how to check and merge the results.

`matt-with-orca` fills that gap with one skill:

- It **locates** where your work stands (not configured, grilling, spec, tickets, a wave in progress, finished) and suggests one next step.
- It **splits** tickets into waves from their `Blocked by` lines, so only independent tickets run side by side.
- It writes one **common rules** file per wave, so every worker gets the same context and each spec stays four lines long.
- It **checks** each worker's work against the real artifacts (commits, ticket status, a re-run of the key claim) instead of trusting the report.
- It **merges** in ticket order, reviews the **seams** between tickets, then **cleans up** worktrees only when that is safe.

The wave file doubles as a log, so a new session can pick up a half-finished wave where the last one stopped.

## How it works

```
idea ──► grill ──► spec ──► tickets ──► wave 1 ──► wave 2 ──► ... ──► done
        (Matt's skills, typed by you)    (this skill + Orca workers)
```

Each run starts by locating the current stage from what is on disk:

| Stage | Signal in the repo | Suggested next step |
|---|---|---|
| A. Not configured | no `docs/agents/issue-tracker.md` | `/mattpocock-skills:setup-matt-pocock-skills` |
| B. Idea not sharp | no spec, terms missing from `CONTEXT.md` | `/mattpocock-skills:grill-with-docs` |
| C. Grilled, no spec | decisions in `CONTEXT.md` or an ADR | `/mattpocock-skills:prototype` or `/mattpocock-skills:to-spec` |
| D. Spec, no tickets | spec exists, `issues/` empty | `/mattpocock-skills:to-tickets` |
| E. Tickets, no wave yet | tickets exist, no `wave*-common-rules.md` | start wave 1 |
| F. Wave in progress | a wave file with unfinished tickets | resume the missing step |
| G. Finished | every ticket `resolved` or `ready-for-human` | summary |

Each wave then goes through the same loop:

1. **Prepare**: check the Orca toolchain (the install part is stamped per Orca version, the session part is checked every run), then read the ticket tracker and the integration branch.
2. **Split**: draw the dependency graph and propose the next wave. You approve it.
3. **Common rules**: pin a base commit and write `wave<N>-common-rules.md` from the template.
4. **Spawn**: one Orca Run per wave, one `worker-start` per ticket. Symptom tickets run `diagnosing-bugs` then `tdd`; behaviour tickets run `tdd`. Every flow ends with `code-review`, as Matt's `/implement` does.
5. **Check**: wait on `worker_done`, then verify each report against commits, ticket status, the review result, and a re-run of its key claim.
6. **Merge**: one `--no-ff` merge per ticket, in ticket order, with a cheap verification after each.
7. **Review the seams**: for waves of two or more tickets, one `code-review` pass over where the tickets touch; findings go to a worker in the owning worktree or get fixed on the integration branch.
8. **Clean up**: remove worktrees whose dispatch has settled, whose tree is clean, and whose branch is merged; then open the next wave.

The skill asks for your approval at the decisions that are yours: the stage and next step, the wave plan, and any question a review raises.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- The Orca app with its `orca` CLI on PATH (tested with Orca 1.4.210), and its two skills installed: `orca skills install --skill orca-cli --skill orchestration`
- **The coordinating Claude Code session must run inside an Orca-managed terminal**: a Run binds to the coordinator's terminal, so `orca worktree current --json` has to resolve to your repo
- [Matt Pocock's skills](https://github.com/mattpocock/skills), installed as the `mattpocock-skills` Claude Code plugin. The skill suggests commands in the plugin's namespaced form, `/mattpocock-skills:<skill>`; if you installed Matt's skills another way, type the same skill without the prefix (`/<skill>`).
- A git repository whose tracker is configured by `/mattpocock-skills:setup-matt-pocock-skills`

[`SETUP.md`](skills/matt-with-orca/SETUP.md) walks through each of these when a check fails.

## Installation

The repo follows the [Agent Skills](https://agentskills.io/specification) layout (`skills/matt-with-orca/SKILL.md`) and is also a Claude Code plugin marketplace, so any of these works. Pick one; installing twice gives you two copies of the command.

### Option 1: Claude Code plugin

```
/plugin marketplace add hanh9898/matt-with-orca
/plugin install matt-with-orca@matt-with-orca
```

Updates arrive through `/plugin marketplace update`. Plugin skills are namespaced, so the command is `/matt-with-orca:matt-with-orca`.

### Option 2: `npx skills`

```bash
npx skills add hanh9898/matt-with-orca -g -a claude-code
```

`-g` installs for your user; drop it to install into the current project. The command is `/matt-with-orca`.

### Option 3: GitHub CLI (v2.90+)

```bash
gh skill install hanh9898/matt-with-orca matt-with-orca --agent claude-code --scope user
```

This resolves the latest tagged release; add `--pin v0.1.0` to fix a version. The command is `/matt-with-orca`.

### Option 4: Manual copy

macOS / Linux:

```bash
git clone https://github.com/hanh9898/matt-with-orca.git
cp -r matt-with-orca/skills/matt-with-orca ~/.claude/skills/
```

Windows (PowerShell):

```powershell
git clone https://github.com/hanh9898/matt-with-orca.git
Copy-Item -Recurse matt-with-orca\skills\matt-with-orca "$env:USERPROFILE\.claude\skills\"
```

To use it in one project only, copy it into that project's `.claude/skills/` instead. The command is `/matt-with-orca`.

## Usage

In a Claude Code session running in an Orca terminal inside your repository (with the plugin install, use `/matt-with-orca:matt-with-orca`):

```
/matt-with-orca
/matt-with-orca <feature name or ticket folder>
```

The skill is user-invoked only (`disable-model-invocation: true`): it starts workers and merges branches, so it runs when you ask for it.

Files it writes:

- `wave<N>-common-rules.md`, next to your ticket folder: the rules every worker of wave N reads, followed by the wave's worker table (Run id, task and dispatch ids) and review log.
- `.installed-version`, in the skill's own directory: the stamp that lets step 1 skip the install checks until Orca changes version. Deleting it forces a full check.

Files in this repo:

| File | Purpose |
|---|---|
| [`skills/matt-with-orca/SKILL.md`](skills/matt-with-orca/SKILL.md) | The coordinator: locate, then steps 1 to 8 |
| [`skills/matt-with-orca/COMMON-RULES-TEMPLATE.md`](skills/matt-with-orca/COMMON-RULES-TEMPLATE.md) | The frame for each wave's common rules |
| [`skills/matt-with-orca/TROUBLESHOOTING.md`](skills/matt-with-orca/TROUBLESHOOTING.md) | Symptoms and fixes for failed starts, stopped workers, merge problems, and cleanup |
| [`skills/matt-with-orca/SETUP.md`](skills/matt-with-orca/SETUP.md) | Installing the Orca CLI, runtime, skills, and Matt's plugin when a step 1 check fails |
| [`.claude-plugin/`](.claude-plugin/) | Marketplace and plugin manifests for the Claude Code plugin install |

## Design principles

- **Every step ends on a checkable "done when".** The coordinator can tell finished from unfinished without judgement calls.
- **Check artifacts, not reports.** A worker's "all green" only covers what it checked.
- **Red before green.** A bug fix counts only if its test failed on the symptom before the fix.
- **Review per ticket, then the seams.** Each worker ends with Matt's `code-review` before its last commit, as `/implement` does; the coordinator reviews only where tickets collide once merged, and skips that pass for one-ticket waves.
- **Only positive evidence acts.** A worker is stopped, abandoned or retried only on proof it exited; silence and `unverifiable` mean keep waiting.
- **Nothing destructive without three checks.** A worktree is removed only when its dispatch has settled, its tree is clean, and its branch is merged.
- **State lives on disk.** Ticket status and the wave file are enough for a fresh session to resume.

## Limitations

- Tested with Claude Code as coordinator and worker, on Windows 11 with Orca 1.4.210, on one sandbox project. Other agents Orca can launch (`codex`, ...) should work if they can load Matt Pocock's skills, but have not been tried.
- Two incidents from that testing are handled in `TROUBLESHOOTING.md` rather than prevented: `worker-start` can return `outcome_unknown` with the spec stuck unsubmitted in the agent's input box, and Orca can place worktrees inside the main checkout, where tree-scanning test runners pick up unmerged code.
- Workers can only run model-invocable skills. `implement`, `to-spec`, `to-tickets`, `grill-with-docs`, `triage`, and `wayfinder` are user-only, so the coordinator suggests them and you type them.
- The ticket tracker is whatever `setup-matt-pocock-skills` configured; the skill reads it but does not create one.

## Contributing

Issues and pull requests are welcome. The skill follows Matt Pocock's [`writing-for-agents`](https://github.com/mattpocock/skills) guidance, so a good change usually:

- adds a row to a table rather than a new prose branch (new flows go in the step 4 flow table);
- gives every step a checkable completion criterion;
- moves material only some runs need into `TROUBLESHOOTING.md`, `SETUP.md` or a new file behind a pointer, keeping `SKILL.md` short.

When a fix comes from a real incident, describe the symptom you saw in the pull request.

## Acknowledgements

- [Matt Pocock](https://github.com/mattpocock) for the [skills](https://github.com/mattpocock/skills) this orchestrates (MIT).
- [Orca](https://github.com/stablyai/orca) for the orchestration layer and worktree management.

## License

[MIT](LICENSE)
