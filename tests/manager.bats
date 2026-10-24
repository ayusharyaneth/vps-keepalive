# Bats tests for the vps-keepalive manager, using the mock tmux.
# Real-tmux coverage lives in tmux.bats (CI only).
# shellcheck shell=bats

setup() {
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  export MOCK_TMUX_STATE="$TEST_TMP/mock"
  export VPS_KEEPALIVE_BIN_DIR="$HOME/.local/bin"
  export VPS_KEEPALIVE_STATE_DIR="$HOME/.local/state/vps-keepalive"
  PATH="$BATS_TEST_DIRNAME/mock:$PATH" # prepended, not exported globally
  export PATH
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SLEEPER_PID=""
  run bash "$ROOT/install.sh"
  [ "$status" -eq 0 ]
}

teardown() {
  if [ -n "$SLEEPER_PID" ]; then
    kill "$SLEEPER_PID" 2>/dev/null || true
  fi
  bash "$ROOT/vps-keepalive" stop >/dev/null 2>&1 || true
  rm -rf "$TEST_TMP"
}

@test "install.sh places both scripts in ~/.local/bin" {
  [ -x "$VPS_KEEPALIVE_BIN_DIR/vps-keepalive" ]
  [ -x "$VPS_KEEPALIVE_BIN_DIR/vps-keepalive-heartbeat" ]
}

@test "start, status, and duplicate-start protection" {
  run bash "$ROOT/vps-keepalive" start
  [ "$status" -eq 0 ]
  [[ "$output" == *'Started'* ]]
  run bash "$ROOT/vps-keepalive" status
  [ "$status" -eq 0 ]
  run bash "$ROOT/vps-keepalive" start
  [ "$status" -eq 0 ]
  [[ "$output" == *'Already running'* ]]
  [ "$(wc -l <"$MOCK_TMUX_STATE/sessions")" -eq 1 ]
}

@test "stop removes the session and is idempotent" {
  bash "$ROOT/vps-keepalive" start >/dev/null 2>&1
  run bash "$ROOT/vps-keepalive" stop
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_TMUX_STATE/sessions" ]
  run bash "$ROOT/vps-keepalive" stop
  [ "$status" -eq 0 ]
  [[ "$output" == *'Not running'* ]]
}

@test "start recovers from a stale session" {
  # Leave a session whose window process is alive but is NOT the heartbeat.
  bash "$ROOT/vps-keepalive" stop >/dev/null 2>&1
  sleep 300 & SLEEPER_PID=$!
  printf 'vps-keepalive\t%s\n' "$SLEEPER_PID" >>"$MOCK_TMUX_STATE/sessions"
  run bash "$ROOT/vps-keepalive" start
  [ "$status" -eq 0 ]
  [[ "$output" == *'stale'* ]]
  [ "$(wc -l <"$MOCK_TMUX_STATE/sessions")" -eq 1 ]
}

@test "status fails when nothing is running" {
  run bash "$ROOT/vps-keepalive" status
  [ "$status" -eq 1 ]
}

@test "logs reports a missing log file gracefully" {
  # install.sh creates an empty log file on purpose; remove it to test the
  # friendly message for a fresh/uninstalled system.
  rm -f "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log"
  run bash "$ROOT/vps-keepalive" logs
  [ "$status" -eq 0 ]
  [[ "$output" == *'No log file yet'* ]]
}

@test "uninstall keeps logs, --purge removes them" {
  bash "$ROOT/vps-keepalive" start >/dev/null 2>&1
  run bash "$ROOT/vps-keepalive" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$VPS_KEEPALIVE_BIN_DIR/vps-keepalive" ]
  [ -f "$VPS_KEEPALIVE_STATE_DIR/heartbeat.log" ]
  run bash "$ROOT/vps-keepalive" uninstall --purge
  [ "$status" -eq 0 ]
  [ ! -e "$VPS_KEEPALIVE_STATE_DIR" ]
}
