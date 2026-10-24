# End-to-end tests against REAL tmux. These run in CI (ubuntu-latest with
# tmux installed) and are skipped automatically where tmux is unavailable.
# shellcheck shell=bash

setup() {
  if ! command -v tmux >/dev/null 2>&1; then
    skip "tmux not available"
  fi
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  export VPS_KEEPALIVE_BIN_DIR="$HOME/.local/bin"
  export VPS_KEEPALIVE_STATE_DIR="$HOME/.local/state/vps-keepalive"
  # Use a dedicated session name so we never touch unrelated tmux sessions.
  export VPS_KEEPALIVE_SESSION="vps-keepalive-ci-$$"
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run bash "$ROOT/install.sh"
  [ "$status" -eq 0 ]
}

teardown() {
  if command -v tmux >/dev/null 2>&1; then
    bash "$ROOT/vps-keepalive" stop >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_TMP"
}

@test "real tmux: start creates a detached session with a live heartbeat" {
  run bash "$ROOT/vps-keepalive" start
  [ "$status" -eq 0 ]
  tmux has-session -t "$VPS_KEEPALIVE_SESSION"
  run bash "$ROOT/vps-keepalive" status
  [ "$status" -eq 0 ]
}

@test "real tmux: duplicate start is rejected without a second session" {
  bash "$ROOT/vps-keepalive" start >/dev/null 2>&1
  run bash "$ROOT/vps-keepalive" start
  [ "$status" -eq 0 ]
  [[ "$output" == *'Already running'* ]]
  [ "$(tmux list-sessions -F '#S' 2>/dev/null | grep -c "^$VPS_KEEPALIVE_SESSION$")" -eq 1 ]
}

@test "real tmux: heartbeat logs a startup entry immediately" {
  bash "$ROOT/vps-keepalive" start >/dev/null 2>&1
  sleep 1
  grep -q 'startup:' "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
  grep -q 'heartbeat ok' "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
}

@test "real tmux: stop kills the session" {
  bash "$ROOT/vps-keepalive" start >/dev/null 2>&1
  run bash "$ROOT/vps-keepalive" stop
  [ "$status" -eq 0 ]
  run ! tmux has-session -t "$VPS_KEEPALIVE_SESSION" 2>/dev/null
}

@test "real tmux: session survives after the controlling shell exits" {
  # Simulate SSH disconnect: start via a detached subshell that then exits.
  bash -c "bash '$ROOT/vps-keepalive' start" >/dev/null 2>&1
  sleep 1
  tmux has-session -t "$VPS_KEEPALIVE_SESSION"
}
