# Common rules template for a wave

Copy the frame below into `wave<N>-common-rules.md` and fill in each section. Each section answers a question every worker in the wave would otherwise ask itself; answered here once, no worker has to guess.

Steps 4 and 7 of the skill append two sections, `## Wave workers` and `## Review`, to the end of the file; leave both out when writing the rules.

Copy in only what a worker cannot look up: an unwritten convention, the reason behind a choice, a trap already hit. Anything one command or one file answers (scripts in `package.json`, the directory layout, `CLAUDE.md`) gets a pointer, not a copy.

```markdown
# Common rules for wave <N> (tickets <NN>, <NN>)

## Graph
`<one-line graph from step 2, e.g. 01✓ → {02, 03?} → 04>`

| Ticket | Status | Blocked by | Wave |
|---|---|---|---|
| <NN> | <status> | <NN, NN or -> | <N, or what blocks it> |

## Context
- Your worktree branches off `<integration branch>` at `<base commit>`, unless your spec names another base commit
  (a ticket started mid-wave). That branch already contains tickets <...>.
  Run `git branch --show-current` before every commit.
- Read before you start: <spec>, <glossary / CONTEXT.md>, <ADRs>, your ticket, and the comments
  of tickets <...> for decisions already made.
- <k> other workers are working the remaining tickets of this wave in parallel, on other branches.
  Work only on your own ticket.

## Existing interfaces to reuse
- `<function / hook / module>`: <signature>, <what it returns>, <what it already handles, e.g. sending mail, logging>.
- Business rules go through the interfaces above; new layers only call them.

## File zones
- Ticket <NN> writes in `<own file>`; ticket <NN> writes in `<own file>`.
- Shared files (<manifest, package index, route table, permission file>): add only your own lines, and keep
  the order of the existing lines.

## Traps already hit
- <trap>: <symptom>, <how to avoid it>, <how to check you avoided it>.

## Resources
- Your private resources are listed in your spec (database, port, volume, temp directory). Use exactly that set.
- Shared resources, read-only: <main container, source database, another session's browser profile>.

## Repo and user rules
- <commit and comment language>, <accepted way to verify>, <lint command>, <test accounts>.

## Asking when stuck
- A blocking question goes through the `ask` command in your preamble; wait for the answer. The coordinator
  answers through Orca; a local question prompt is seen by no one.

## Done means
- Commit to your branch. The coordinator pushes and merges.
- Before the last commit: run `/mattpocock-skills:code-review` with your base commit as the fixed point, fix the
  findings, and write the number of findings per axis and the outcome of each into the ticket's comments.
- Change the ticket status: `resolved` if fully done, `ready-for-human` for the part a human must do.
  Write a full report in the ticket's comments: a design summary, files touched, how you verified with
  evidence, work not done or still in doubt, and decisions the user must make.
- Clean up your private resources; state the reason for anything you keep.
- Send `worker_done` exactly once, per your preamble: a three-sentence summary, `--outcome succeeded` when the
  ticket is `resolved`, `--outcome failed` when it could not be done, with `--files-modified`.
```
