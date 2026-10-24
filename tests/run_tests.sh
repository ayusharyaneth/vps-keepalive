#!/usr/bin/env bash
# tests/run_tests.sh — portable test suite for vps-keepalive.
#
# Runs anywhere bash runs (no tmux required: a mock tmux simulates detached
# sessions). Coverage:
#   1. Shell syntax (bash -n) for every script
#   2. ShellCheck, when available
#   3. End-to-end manager flow against the mock tmux:
#      install -> start -> duplicate start -> status -> logs -> restart -> stop
#   4. Stale-session recovery (session exists but heartbeat is dead)
#   5. Heartbeat: immediate first beat, repeated beats, IST timestamps,
#      survival of failing heartbeat commands, clean shutdown on SIGTERM
#   6. Uninstall (logs kept; --purge removes them)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
PASS=0
FAIL=0
declare -a CLEANUP_PIDS=()

cleanup() {
  local p
  for p in "${CLEANUP_PIDS[@]:-}"; do
    [ -n "$p" ] && kill "$p" 2>/dev/null
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

ok()   { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

check() { # check DESCRIPTION CONDITION-COMMAND...
  local desc="$1"; shift
  if "$@"; then
    ok "$desc"
  else
    fail "$desc"
  fi
}

check_eq() { # check_eq DESCRIPTION EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1 (expected [$2], got [$3])"
  fi
}

grep_q() { grep -q "$1" "$2" 2>/dev/null; }

TEST_HOME="$TMP/home"
export MOCK_TMUX_STATE="$TMP/mock"
export VPS_KEEPALIVE_BIN_DIR="$TEST_HOME/.local/bin"
export VPS_KEEPALIVE_STATE_DIR="$TEST_HOME/.local/state/vps-keepalive"
export PATH="$ROOT/tests/mock:$PATH"
LOG_FILE="$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"

printf '\n== 1. Shell syntax ==\n'
# Note: *.bats files use Bats syntax and are validated by bats itself in CI;
# bash -n cannot parse `@test "..." { ... }` blocks.
for f in "$ROOT/heartbeat.sh" "$ROOT/vps-keepalive" "$ROOT/install.sh" \
         "$ROOT/tests/mock/tmux" "$ROOT/tests/run_tests.sh"; do
  check_eq "bash -n $(basename "$f")" "0" "$(bash -n "$f" >/dev/null 2>&1; echo $?)"
done

printf '\n== 2. ShellCheck (skipped silently if not installed) ==\n'
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x "$ROOT/heartbeat.sh" "$ROOT/vps-keepalive" "$ROOT/install.sh" \
       "$ROOT/tests/mock/tmux" "$ROOT/tests/run_tests.sh"; then
    ok "shellcheck passed"
  else
    fail "shellcheck reported problems"
  fi
else
  printf '     (shellcheck not found locally; CI runs it)\n'
fi

printf '\n== 3. Installer (local mode, temp HOME) ==\n'
HOME="$TEST_HOME" bash "$ROOT/install.sh" >"$TMP/install.out" 2>&1
check_eq "install.sh exits 0" "0" "$?"
check "heartbeat installed to BIN_DIR" test -x "$VPS_KEEPALIVE_BIN_DIR/vps-keepalive-heartbeat"
check "manager installed to BIN_DIR"   test -x "$VPS_KEEPALIVE_BIN_DIR/vps-keepalive"
check "state directory created"        test -d "$VPS_KEEPALIVE_STATE_DIR"
# Idempotency: a second install must succeed too.
HOME="$TEST_HOME" bash "$ROOT/install.sh" >/dev/null 2>&1
check_eq "re-install is idempotent" "0" "$?"

printf '\n== 4. Manager: start / duplicate start / status / logs / restart ==\n'
bash "$ROOT/vps-keepalive" start >"$TMP/start.out" 2>&1
check_eq "start exits 0" "0" "$?"
check "session registered by tmux (mock)" grep_q "vps-keepalive" "$MOCK_TMUX_STATE/sessions"
HB_PID="$(awk -F'\t' '$1=="vps-keepalive" {print $2}' "$MOCK_TMUX_STATE/sessions")"
CLEANUP_PIDS+=("$HB_PID")
check "heartbeat process is alive after start" kill -0 "$HB_PID" 2>/dev/null
check "startup line logged" grep_q "startup:" "$LOG_FILE"

SESSIONS_BEFORE="$(wc -l <"$MOCK_TMUX_STATE/sessions")"
bash "$ROOT/vps-keepalive" start >"$TMP/start2.out" 2>&1
check_eq "duplicate start exits 0 (idempotent)" "0" "$?"
check_eq "duplicate start did not create a second session" "$SESSIONS_BEFORE" "$(wc -l <"$MOCK_TMUX_STATE/sessions")"
check "duplicate start mentions 'Already running'" grep_q "Already running" "$TMP/start2.out"

bash "$ROOT/vps-keepalive" status >"$TMP/status.out" 2>&1
check_eq "status exits 0 while running" "0" "$?"
check "status reports running session" grep_q "running" "$TMP/status.out"
check "status carries the local-only disclaimer" grep_q "does not verify" "$TMP/status.out"

bash "$ROOT/vps-keepalive" logs >"$TMP/logs.out" 2>&1
check_eq "logs exits 0" "0" "$?"
check "logs show the startup entry" grep_q "startup:" "$TMP/logs.out"

bash "$ROOT/vps-keepalive" restart >"$TMP/restart.out" 2>&1
check_eq "restart exits 0" "0" "$?"
check_eq "restart keeps exactly one session" "1" "$(wc -l <"$MOCK_TMUX_STATE/sessions")"
HB_PID="$(awk -F'\t' '$1=="vps-keepalive" {print $2}' "$MOCK_TMUX_STATE/sessions")"
CLEANUP_PIDS+=("$HB_PID")
check "heartbeat alive after restart" kill -0 "$HB_PID" 2>/dev/null

bash "$ROOT/vps-keepalive" attach >/dev/null 2>&1
check_eq "attach exits 0 while session exists" "0" "$?"
bash "$ROOT/vps-keepalive" detach >"$TMP/detach.out" 2>&1
check_eq "detach exits 0" "0" "$?"

printf '\n== 5. Stale-session recovery ==\n'
# Section 4 leaves a live session; stop it, then simulate a session that
# exists but whose window process is NOT the heartbeat (the mock keeps a
# session while its recorded PID is alive): run a throwaway sleeper and
# register it as the session's process.
bash "$ROOT/vps-keepalive" stop >/dev/null 2>&1
sleep 300 & SLEEPER_PID=$!
CLEANUP_PIDS+=("$SLEEPER_PID")
printf 'vps-keepalive\t%s\n' "$SLEEPER_PID" >>"$MOCK_TMUX_STATE/sessions"
bash "$ROOT/vps-keepalive" start >"$TMP/stale.out" 2>&1
check_eq "start over stale session exits 0" "0" "$?"
check "stale session was reported" grep_q "stale" "$TMP/stale.out"
check_eq "exactly one session after recovery" "1" "$(wc -l <"$MOCK_TMUX_STATE/sessions")"
HB_PID="$(awk -F'\t' '$1=="vps-keepalive" {print $2}' "$MOCK_TMUX_STATE/sessions")"
CLEANUP_PIDS+=("$HB_PID")
check "fresh heartbeat alive after recovery" kill -0 "$HB_PID" 2>/dev/null

printf '\n== 6. Manager: stop ==\n'
bash "$ROOT/vps-keepalive" stop >"$TMP/stop.out" 2>&1
check_eq "stop exits 0" "0" "$?"
check "session removed" [ ! -s "$MOCK_TMUX_STATE/sessions" ]
sleep 1
HB_PID="$(awk -F'\t' '$1=="vps-keepalive" {print $2}' "$MOCK_TMUX_STATE/sessions" 2>/dev/null)"
check "heartbeat process no longer running" [ -z "$HB_PID" ]
bash "$ROOT/vps-keepalive" stop >/dev/null 2>&1
check_eq "stop when stopped is idempotent" "0" "$?"
bash "$ROOT/vps-keepalive" status >/dev/null 2>&1
check_eq "status exits nonzero when stopped" "1" "$?"

printf '\n== 7. Heartbeat: timing, IST timestamps, failure tolerance, shutdown ==\n'
HB_STATE="$TMP/hbtest"
BEFORE_UTC="$(date -u +%s)"
VPS_KEEPALIVE_STATE_DIR="$HB_STATE" VPS_KEEPALIVE_INTERVAL=1 VPS_KEEPALIVE_CMD=true \
  bash "$ROOT/heartbeat.sh" >"$TMP/hb.stdout" 2>&1 &
HB_PID=$!
CLEANUP_PIDS+=("$HB_PID")
sleep 4
kill -TERM "$HB_PID" 2>/dev/null
wait "$HB_PID" 2>/dev/null
HB_LOG="$HB_STATE/heartbeat.log"
check "heartbeat log created" test -f "$HB_LOG"
check "startup logged" grep_q "startup:" "$HB_LOG"
BEATS="$(grep -c 'heartbeat ok' "$HB_LOG")"
# MSYS/Windows process spawning is slow (~2s per loop), so this floor is
# deliberately modest; the Bats suite on Linux asserts >= 3 beats.
check "immediate beat plus repeats within ~5s (got $BEATS beats, need >= 2)" [ "$BEATS" -ge 2 ]
check "clean shutdown logged on SIGTERM" grep_q "shutdown:" "$HB_LOG"

# IST check: a logged wall-clock time parsed as UTC should be 5h30m behind
# the real epoch (IST = UTC+05:30). Allow a generous 90s of slop.
IST_LINE="$(grep -m1 'heartbeat ok' "$HB_LOG" || true)"
IST_TS="$(printf '%s' "$IST_LINE" | sed -E 's/^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}) .*/\1/')"
if [ -n "$IST_TS" ] && [ "${#IST_TS}" -eq 19 ]; then
  AS_UTC="$(date -u -d "$IST_TS" +%s 2>/dev/null)" || AS_UTC=""
  if [ -n "$AS_UTC" ]; then
    DRIFT=$(( BEFORE_UTC - (AS_UTC - 19800) ))
    check "timestamp is IST (drift ${DRIFT}s, must be within +-90s)" \
      sh -c "[ $DRIFT -ge -90 ] && [ $DRIFT -le 90 ]"
  else
    fail "timestamp is IST (could not parse '$IST_TS')"
  fi
else
  fail "timestamp is IST (no parseable timestamp line)"
fi

# Command failures must be logged and survived, never fatal.
VPS_KEEPALIVE_STATE_DIR="$TMP/hbfail" VPS_KEEPALIVE_INTERVAL=1 VPS_KEEPALIVE_CMD=false \
  bash "$ROOT/heartbeat.sh" >"$TMP/hbfail.stdout" 2>&1 &
HB_PID=$!
CLEANUP_PIDS+=("$HB_PID")
sleep 2.5
check "heartbeat survives a failing command" kill -0 "$HB_PID" 2>/dev/null
check "failing command logged as WARN" grep_q "heartbeat FAILED" "$TMP/hbfail/heartbeat.log"
kill -TERM "$HB_PID" 2>/dev/null
wait "$HB_PID" 2>/dev/null

printf '\n== 8. Uninstall ==\n'
bash "$ROOT/vps-keepalive" start >/dev/null 2>&1
bash "$ROOT/vps-keepalive" uninstall >"$TMP/uninstall.out" 2>&1
check_eq "uninstall exits 0" "0" "$?"
check "manager binary removed" [ ! -e "$VPS_KEEPALIVE_BIN_DIR/vps-keepalive" ]
check "heartbeat binary removed" [ ! -e "$VPS_KEEPALIVE_BIN_DIR/vps-keepalive-heartbeat" ]
check "logs kept without --purge" test -f "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
bash "$ROOT/vps-keepalive" uninstall --purge >/dev/null 2>&1
check_eq "uninstall --purge exits 0" "0" "$?"
check "logs removed with --purge" [ ! -e "$VPS_KEEPALIVE_STATE_DIR" ]

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
printf 'All tests passed.\n'
