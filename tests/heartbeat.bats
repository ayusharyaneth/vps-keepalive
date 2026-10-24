# Bats tests for heartbeat.sh. These run in CI (ubuntu-latest).
# The full portable suite lives in tests/run_tests.sh.
# shellcheck shell=bash

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

@test "heartbeat logs startup, repeated beats, and clean shutdown" {
  VPS_KEEPALIVE_CMD=true bash "$ROOT/heartbeat.sh" >/dev/null 2>&1 &
  HB_PID=$!
  sleep 6
  [ -f "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log" ]
  grep -q 'startup:' "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
  local beats
  beats="$(grep -c 'heartbeat ok' "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log")"
  # >= 2 proves an immediate beat plus at least one repeat; slow hosts
  # (MSYS) may take ~3s per loop iteration under load.
  [ "$beats" -ge 2 ]
  kill -TERM "$HB_PID"
  wait "$HB_PID" 2>/dev/null || true
  grep -q 'shutdown:' "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
}

@test "heartbeat keeps running when the command fails" {
  VPS_KEEPALIVE_CMD=false bash "$ROOT/heartbeat.sh" >/dev/null 2>&1 &
  HB_PID=$!
  sleep 4
  kill -0 "$HB_PID"
  grep -q 'heartbeat FAILED' "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
}

@test "timestamps are in IST (UTC+05:30)" {
  VPS_KEEPALIVE_CMD=true bash "$ROOT/heartbeat.sh" >/dev/null 2>&1 &
  HB_PID=$!
  sleep 3
  local before log ts as_utc drift
  # before was captured ~1-2s before the beat; recompute generously.
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

@test "rejects a non-numeric interval" {
  run env VPS_KEEPALIVE_INTERVAL=abc VPS_KEEPALIVE_STATE_DIR="$TEST_TMP/x" bash "$ROOT/heartbeat.sh"
  [ "$status" -eq 1 ]
}
