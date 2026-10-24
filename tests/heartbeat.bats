# Bats tests for heartbeat.sh. These run in CI (ubuntu-latest).
# The full portable suite lives in tests/run_tests.sh.
# shellcheck shell=bats

setup() {
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  export VPS_KEEPALIVE_STATE_DIR="$TEST_TMP/state"
  export VPS_KEEPALIVE_INTERVAL=1
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

teardown() {
  if [ -n "${HB_PID:-}" ]; then
    kill -TERM "$HB_PID" 2>/dev/null || true
    wait "$HB_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_TMP"
}

# Poll until the log file exists (process spawn can take seconds on slow
# or heavily loaded hosts), then until it contains at least N occurrences
# of PATTERN.
wait_for_log() { # wait_for_log MAX_SECONDS
  local waited=0
  while :; do
    [ -f "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log" ] && return 0
    [ "$waited" -ge "$1" ] && return 1
    sleep 1
    waited=$((waited + 1))
  done
}

wait_for_beats() { # wait_for_beats PATTERN N MAX_SECONDS
  local pattern="$1" want="$2" max="$3" waited=0
  while :; do
    [ "$(grep -c "$pattern" "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log" 2>/dev/null)" -ge "$want" ] && return 0
    [ "$waited" -ge "$max" ] && return 1
    sleep 1
    waited=$((waited + 1))
  done
}

@test "heartbeat logs startup, repeated beats, and clean shutdown" {
  VPS_KEEPALIVE_CMD=true bash "$ROOT/heartbeat.sh" >/dev/null 2>&1 &
  HB_PID=$!
  wait_for_log 20
  grep -q 'startup:' "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
  # >= 2 proves an immediate beat plus at least one repeat.
  wait_for_beats 'heartbeat ok' 2 20
  kill -TERM "$HB_PID"
  wait "$HB_PID" 2>/dev/null || true
  grep -q 'shutdown:' "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
}

@test "heartbeat keeps running when the command fails" {
  VPS_KEEPALIVE_CMD=false bash "$ROOT/heartbeat.sh" >/dev/null 2>&1 &
  HB_PID=$!
  wait_for_beats 'heartbeat FAILED' 1 20
  kill -0 "$HB_PID"
}

@test "timestamps are in IST (UTC+05:30)" {
  VPS_KEEPALIVE_CMD=true bash "$ROOT/heartbeat.sh" >/dev/null 2>&1 &
  HB_PID=$!
  wait_for_beats 'heartbeat ok' 1 20
  local before log ts as_utc drift
  before="$(date -u +%s)"
  log="$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
  ts="$(grep -m1 'heartbeat ok' "$log" | sed -E 's/^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}) .*/\1/')"
  [ "${#ts}" -eq 19 ]
  as_utc="$(date -u -d "$ts" +%s)"
  kill -TERM "$HB_PID"
  wait "$HB_PID" 2>/dev/null || true
  # A wall time parsed as UTC should sit 5h30m behind real time.
  drift=$(( before - (as_utc - 19800) ))
  [ "$drift" -ge -90 ] && [ "$drift" -le 90 ]
}

@test "VPS_KEEPALIVE_BEATS splits the interval into evenly spaced beats" {
  VPS_KEEPALIVE_CMD=true VPS_KEEPALIVE_INTERVAL=6 VPS_KEEPALIVE_BEATS=3 \
    bash "$ROOT/heartbeat.sh" >/dev/null 2>&1 &
  HB_PID=$!
  wait_for_log 20
  grep -q 'beats=3/interval (every 2s)' "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
  # 6s / 3 beats = one beat every 2s.
  wait_for_beats 'heartbeat ok' 3 30
}

@test "rejects a non-numeric interval" {
  run env VPS_KEEPALIVE_INTERVAL=abc VPS_KEEPALIVE_STATE_DIR="$TEST_TMP/x" bash "$ROOT/heartbeat.sh"
  [ "$status" -eq 1 ]
}
