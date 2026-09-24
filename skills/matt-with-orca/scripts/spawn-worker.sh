#!/usr/bin/env bash
# Spawn one supervised Orca worker warm: start the agent, wait until its input box is on
# screen, then hand it the Task with `worker-start --terminal`. Run one per ticket, in the
# shell's background mode, and read the RESULT line when it finishes.
#
# New worktree (step 4):
#   spawn-worker.sh --new --repo <selector> --name <name> --base <branch> --agent <id> \
#     --display-name <text> --title <task title> --spec-file <path>
# Existing worktree (step 7 fixes, retries):
#   spawn-worker.sh --worktree <repoId::path> --launch "<agent command>" \
#     (--title <task title> --spec-file <path> | --task <task id> --retry-of <dispatch id>)
#
# Options: --warm <text> (default "bypass permissions": Claude Code as Orca launches it),
#          --warm-timeout <seconds> (default 120).
# Output: progress lines, then one line starting with RESULT, with worktree, handle, task,
# dispatch, state, stage and error. The full receipt is saved next to the spec file, or in
# the temp directory.
set -u

MODE=""; REPO=""; NAME=""; BASE=""; AGENT=""; DISPLAY=""; WT=""; LAUNCH=""
TITLE=""; SPEC_FILE=""; TASK=""; RETRY_OF=""; WARM="bypass permissions"; WARM_TIMEOUT=120
while [ $# -gt 0 ]; do
  case "$1" in
    --new) MODE=new ;;
    --worktree) MODE=existing; WT=$2; shift ;;
    --repo) REPO=$2; shift ;;
    --name) NAME=$2; shift ;;
    --base) BASE=$2; shift ;;
    --agent) AGENT=$2; shift ;;
    --display-name) DISPLAY=$2; shift ;;
    --launch) LAUNCH=$2; shift ;;
    --title) TITLE=$2; shift ;;
    --spec-file) SPEC_FILE=$2; shift ;;
    --task) TASK=$2; shift ;;
    --retry-of) RETRY_OF=$2; shift ;;
    --warm) WARM=$2; shift ;;
    --warm-timeout) WARM_TIMEOUT=$2; shift ;;
    *) echo "RESULT error=unknown_option:$1"; exit 2 ;;
  esac
  shift
done

field() { grep -o "\"$1\": *\"[^\"]*\"" | head -1 | sed 's/.*: *"\(.*\)"/\1/'; }

if [ "$MODE" = new ]; then
  C=$(orca worktree create --repo "$REPO" --name "$NAME" --base-branch "$BASE" --no-parent --agent "$AGENT" --json 2>&1)
  WT=$(printf '%s' "$C" | grep -o '"id": *"[^"]*::[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
  H=$(printf '%s' "$C" | grep -A3 '"startupTerminal"' | field handle)
  [ -n "$WT" ] && [ -n "$H" ] || { echo "RESULT error=worktree_create_failed detail=$(printf '%s' "$C" | field code)"; exit 1; }
  [ -n "$DISPLAY" ] && orca worktree set --worktree "id:$WT" --display-name "$DISPLAY" --json >/dev/null 2>&1
elif [ "$MODE" = existing ]; then
  C=$(orca terminal create --worktree "id:$WT" --title "${TITLE:-worker}" --command "$LAUNCH" --json 2>&1)
  H=$(printf '%s' "$C" | field handle)
  [ -n "$H" ] || { echo "RESULT worktree=$WT error=terminal_create_failed detail=$(printf '%s' "$C" | field code)"; exit 1; }
else
  echo "RESULT error=missing_--new_or_--worktree"; exit 2
fi
echo "worktree=$WT handle=$H"

# Warm: the agent's input box is drawn. tui-idle can fire before anything is drawn.
WARMED=""
for i in $(seq 1 "$WARM_TIMEOUT"); do
  if orca terminal read --terminal "$H" --screen 2>/dev/null | grep -qF "$WARM"; then WARMED=$i; break; fi
  sleep 1
done
[ -n "$WARMED" ] || { echo "RESULT worktree=$WT handle=$H error=not_warm_after_${WARM_TIMEOUT}s"; exit 1; }
echo "warm_after=${WARMED}s"

OUT_DIR=$(dirname "${SPEC_FILE:-${TMPDIR:-/tmp}/x}")
RECEIPT="$OUT_DIR/receipt-$(date +%s)-$$.json"
for try in 1 2 3 4 5 6; do
  if [ -n "$TASK" ]; then
    # A retry reuses the Task's stored spec; --task and --spec are mutually exclusive.
    R=$(orca orchestration worker-start --task "$TASK" ${RETRY_OF:+--retry-of "$RETRY_OF"} \
      --terminal "$H" --worktree "id:$WT" --json 2>&1)
  else
    R=$(orca orchestration worker-start --spec "$(cat "$SPEC_FILE")" --task-title "$TITLE" \
      --terminal "$H" --worktree "id:$WT" --json 2>&1)
  fi
  CODE=$(printf '%s' "$R" | field code)
  [ "$CODE" = agent_unconfigured ] || break
  echo "agent_unconfigured, retry $try"   # no Task was created; safe to repeat
  sleep 5
done
printf '%s' "$R" > "$RECEIPT"

echo "RESULT worktree=$WT handle=$H task=$(printf '%s' "$R" | field taskId) dispatch=$(printf '%s' "$R" | field dispatchId) state=$(printf '%s' "$R" | field state) stage=$(printf '%s' "$R" | field stage) turnStart=$(printf '%s' "$R" | field turnStart) error=${CODE:--} receipt=$RECEIPT"
