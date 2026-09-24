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
#          --warm-timeout <seconds> (default 120); env ORCA_TIMEOUT bounds each orca call (180 s),
#          env ORCA_BIN or ORCA_CLI_COMMAND picks the executable (default orca).
# Output: progress lines, then one line starting with RESULT, with worktree, handle, task,
# request id, dispatch, state, stage and error. The full receipt is saved next to the spec file, or in
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
# Every orca call is bounded: under load a call can hang without returning.
ORCA_TIMEOUT=${ORCA_TIMEOUT:-180}
# The same executable the coordinator resolved (step 1); ORCA_CLI_COMMAND may carry arguments.
ORCA_BIN=${ORCA_BIN:-${ORCA_CLI_COMMAND:-orca}}
o() { timeout "$ORCA_TIMEOUT" $ORCA_BIN "$@"; }
uuid4() { printf '%04x%04x-%04x-4%03x-%04x-%04x%04x%04x' $RANDOM $RANDOM $RANDOM $((RANDOM & 0xfff)) $(((RANDOM & 0x3fff) | 0x8000)) $RANDOM $RANDOM $RANDOM; }

OUT_DIR=$(dirname "${SPEC_FILE:-${TMPDIR:-/tmp}/x}")
STAMP="$(date +%s)-$$"

# Orca mutations run one at a time across every spawn job: parallel `worktree create` calls
# have returned runtime_unavailable for a worktree that was created, dropped startupTerminal,
# or hung; parallel worker-start calls miss the turn start. Warm-ups stay parallel.
LOCK="${TMPDIR:-/tmp}/matt-with-orca-mutate.lock"
lock() { until mkdir "$LOCK" 2>/dev/null; do sleep 1; done; }
unlock() { rmdir "$LOCK" 2>/dev/null; }
trap unlock EXIT

if [ "$MODE" = new ]; then
  lock
  C=$(o worktree create --repo "$REPO" --name "$NAME" --base-branch "$BASE" --no-parent --agent "$AGENT" --json 2>&1)
  RC=$?
  unlock
  printf '%s' "$C" > "$OUT_DIR/create-$STAMP.json"
  WT=$(printf '%s' "$C" | grep -o '"id": *"[^"]*::[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
  H=$(printf '%s' "$C" | grep -A3 '"startupTerminal"' | field handle)
  # Create does not always return startupTerminal: take the agent terminal from the worktree's list.
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -n "$H" ] || [ -z "$WT" ] && break
    sleep 1
    H=$(o terminal list --worktree "id:$WT" --json 2>/dev/null | field handle)
  done
  if [ -z "$WT" ] || [ -z "$H" ]; then
    # Create can answer runtime_unavailable after it made the worktree and launched the agent:
    # adopt that worktree and its agent terminal instead of creating a second one.
    EXISTING=$(git worktree list --porcelain 2>/dev/null | grep '^worktree ' | grep -F "/$NAME" | head -1 | cut -d' ' -f2-)
    if [ -n "$EXISTING" ]; then
      WT="${REPO#id:}::$EXISTING"
      for i in $(seq 1 30); do
        H=$(o terminal list --worktree "id:$WT" --json 2>/dev/null | field handle)
        [ -n "$H" ] && break
        sleep 1
      done
      [ -n "$H" ] && echo "create_recovered detail=$(printf '%s' "$C" | field code)"
    fi
    if [ -z "$H" ]; then
      echo "RESULT worktree=${WT:-?} error=worktree_create_failed rc=$RC detail=$(printf '%s' "$C" | field code) existing=${EXISTING:--} raw=$OUT_DIR/create-$STAMP.json"
      exit 1
    fi
  fi
  [ -n "$DISPLAY" ] && o worktree set --worktree "id:$WT" --display-name "$DISPLAY" --json >/dev/null 2>&1
elif [ "$MODE" = existing ]; then
  C=$(o terminal create --worktree "id:$WT" --title "${TITLE:-worker}" --command "$LAUNCH" --json 2>&1)
  H=$(printf '%s' "$C" | field handle)
  [ -n "$H" ] || { echo "RESULT worktree=$WT error=terminal_create_failed detail=$(printf '%s' "$C" | field code)"; exit 1; }
else
  echo "RESULT error=missing_--new_or_--worktree"; exit 2
fi
echo "worktree=$WT handle=$H"

# Warm: the agent's input box is drawn. tui-idle can fire before anything is drawn.
WARMED=""
for i in $(seq 1 "$WARM_TIMEOUT"); do
  if o terminal read --terminal "$H" --screen 2>/dev/null | grep -qF "$WARM"; then WARMED=$i; break; fi
  sleep 1
done
[ -n "$WARMED" ] || { echo "RESULT worktree=$WT handle=$H error=not_warm_after_${WARM_TIMEOUT}s"; exit 1; }
echo "warm_after=${WARMED}s"

RECEIPT="$OUT_DIR/receipt-$STAMP.json"
lock
for try in 1 2 3 4 5 6; do
  # One request id per attempt, a UUID chosen here so it is known even if the answer never
  # comes: request-show then tells whether the Task and Dispatch were created, and a replay
  # with the same id joins that request instead of starting a second one.
  REQ=$(uuid4)
  if [ -n "$TASK" ]; then
    # A retry reuses the Task's stored spec; --task and --spec are mutually exclusive.
    R=$(o orchestration worker-start --task "$TASK" ${RETRY_OF:+--retry-of "$RETRY_OF"} \
      --terminal "$H" --worktree "id:$WT" --retry-request "$REQ" --json 2>&1)
  else
    R=$(o orchestration worker-start --spec "$(cat "$SPEC_FILE")" --task-title "$TITLE" \
      --terminal "$H" --worktree "id:$WT" --retry-request "$REQ" --json 2>&1)
  fi
  RC=$?
  if [ "$RC" = 124 ]; then
    R=$(o orchestration request-show --request "$REQ" --json 2>&1)
    echo "RESULT worktree=$WT handle=$H request=$REQ error=worker_start_timeout request_state=$(printf '%s' "$R" | field state)"
    exit 1
  fi
  CODE=$(printf '%s' "$R" | field code)
  [ "$CODE" = agent_unconfigured ] || break
  echo "agent_unconfigured, retry $try"   # no Task was created; safe to repeat
  sleep 5
done
unlock
printf '%s' "$R" > "$RECEIPT"

echo "RESULT worktree=$WT handle=$H request=$REQ task=$(printf '%s' "$R" | field taskId) dispatch=$(printf '%s' "$R" | field dispatchId) state=$(printf '%s' "$R" | field state) stage=$(printf '%s' "$R" | field stage) turnStart=$(printf '%s' "$R" | field turnStart) error=${CODE:--} receipt=$RECEIPT"
