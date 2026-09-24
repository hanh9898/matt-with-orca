# Set up the Orca toolchain for matt-with-orca

Read this file when a check in step 1 of the skill fails. Each section: what is missing, how to install it, and how to check again. Work in order; each section builds on the one before.

## 1. The `orca` CLI

The CLI ships with the Orca app; it is not installed separately. On Windows it lives in `%LOCALAPPDATA%\Programs\orca\resources\bin\orca.exe`, and the app adds that directory to PATH.

- `orca --version` does not run: the Orca app is not installed, or PATH lacks the directory above. The user installs the Orca app, then opens a new terminal inside Orca.
- Linux outside an Orca terminal: use `orca-ide`, because `orca` there is usually the GNOME screen reader. If `ORCA_CLI_COMMAND` is set, use its value. Pick one and use it for the whole session.
- `orca skills get` reports an unknown command: the app is too old. The user updates the Orca app from inside the app (the CLI has no app-upgrade command).

**Check again:** `orca --version` prints a version number, and `orca skills get orchestration` prints the guide.

## 2. The Orca runtime

- `orca status --json` reports `result.runtime.reachable: false`: run `orca open --json` and wait for it to return.
- A command reports `runtime_access_denied`: a sandbox blocked the connection. Re-run that same command with elevated permissions; the app is still running, so do not `orca open` or restart Orca.
- `orca worktree current --json` returns no worktree: this session runs outside an Orca-managed terminal. The user opens the repo in Orca (`orca repo add --path <repo>` if it is not there yet) and runs the skill again in an Orca terminal; the Run must bind to the coordinator's terminal.

**Check again:** `result.runtime.reachable: true`, and `orca worktree current --json` returns the worktree of the repo being worked on.

## 3. Orca skills

matt-with-orca needs two Orca skills: `orchestration` (Runs, workers, `worker_done`) and `orca-cli` (worktrees, terminals). Both are stubs pointing at `orca skills get`, so the installed copy must match the CLI version.

- Not installed (missing from `orca skills installed`): `orca skills install --skill orca-cli --skill orchestration`.
- Installed but old: `orca skills update --skill orca-cli --skill orchestration`.

Both commands call `npx skills`, which `git clone`s the whole `stablyai/orca` repo for each skill: several minutes per skill, so run them in the background and wait for them to finish. They need git to reach GitHub; if the network blocks HTTPS, tell the user (see "Environment" in [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)).

**Check again:** `orca skills installed` lists `orca-cli` and `orchestration`.

## 4. Matt Pocock's skills for the workers

Workers run the flow from step 4 (`tdd`, `diagnosing-bugs`, `code-review`), and the coordinator runs `code-review` in step 7 for multi-ticket waves. These skills belong to the Claude Code plugin `mattpocock-skills`, installed at user level so every worktree sees them.

- Missing from `orca skills installed`: the user installs the `mattpocock-skills` plugin with Claude Code's `/plugin` command. An agent cannot install a plugin on its own.
- Workers use an agent other than Claude (`codex`, ...): a Claude plugin does not reach that agent. Paste the flow's method straight into the spec, and record it in the traps section of the common rules.

**Check again:** `orca skills installed` lists `tdd`, `diagnosing-bugs` and `code-review` under `Claude plugin mattpocock-skills`.
