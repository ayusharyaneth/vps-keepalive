#!/usr/bin/env bash
# heartbeat.sh — part of vps-keepalive
#
# Runs a harmless command (default: uptime) immediately at startup and then
# once every VPS_KEEPALIVE_INTERVAL seconds (default: 1200 = 20 minutes),
# optionally split into VPS_KEEPALIVE_BEATS evenly spaced sub-beats (e.g.
# INTERVAL=1800 with BEATS=5 -> one beat every 6 minutes). All events are
# appended to ~/.local/state/vps-keepalive/heartbeat.log with timestamps in
# Indian Standard Time (Asia/Kolkata, UTC+05:30).
#
# TIP: `uptime` generates no measurable CPU/disk activity. If your provider
# monitors resource usage, set VPS_KEEPALIVE_CMD=workload so each beat runs
# vps-keepalive-workload (real CPU + disk work, still fully local).
#
# NOTE: this only generates activity *inside the VPS*. Whether that prevents
# suspension depends entirely on your provider's activity-detection policy.
# See the README ("What this tool can and cannot do") before relying on it.
#
# set -e is deliberately NOT used: the whole point is to keep running even
# when the heartbeat command itself fails. Only unbound variables are fatal.
set -u

INTERVAL="${VPS_KEEPALIVE_INTERVAL:-1200}"
BEATS="${VPS_KEEPALIVE_BEATS:-1}"
HEARTBEAT_CMD="${VPS_KEEPALIVE_CMD:-uptime}"
STATE_DIR="${VPS_KEEPALIVE_STATE_DIR:-${HOME:-/tmp}/.local/state/vps-keepalive}"
LOG_FILE="${STATE_DIR}/heartbeat.log"

# Validate INTERVAL early: a bad value must stop the loop, not silently spin.
case "$INTERVAL" in
  ''|*[!0-9]*)
    printf 'vps-keepalive: VPS_KEEPALIVE_INTERVAL must be a positive integer (got %q)\n' "$INTERVAL" >&2
    exit 1
    ;;
esac
if [ "$INTERVAL" -lt 1 ]; then
  printf 'vps-keepalive: VPS_KEEPALIVE_INTERVAL must be at least 1 second\n' >&2
  exit 1
fi

# BEATS divides one interval into evenly spaced beats. INTERVAL=1800 with
# BEATS=5 means one beat every 6 minutes (five beats per 30-minute window).
case "$BEATS" in
  ''|*[!0-9]*)
    printf 'vps-keepalive: VPS_KEEPALIVE_BEATS must be a positive integer (got %q)\n' "$BEATS" >&2
    exit 1
    ;;
esac
if [ "$BEATS" -lt 1 ]; then
  printf 'vps-keepalive: VPS_KEEPALIVE_BEATS must be at least 1\n' >&2
  exit 1
fi
STEP=$(( INTERVAL / BEATS ))
if [ "$STEP" -lt 1 ]; then
  STEP=1
fi

# Current time formatted for Asia/Kolkata (IST, UTC+05:30, no DST).
# Some minimal systems lack the tzdata database and silently resolve named
# zones to UTC/GMT, so the named zone is only trusted when `date +%z`
# actually reports +0530. Falls back to a POSIX TZ definition (no tzdata
# needed) and finally to UTC.
ist_now() {
  local ts off
  ts="$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)" || ts=""
  off="$(TZ=Asia/Kolkata date '+%z' 2>/dev/null)" || off=""
  if [ "$off" = "+0530" ] && [ -n "$ts" ]; then
    printf '%s' "$ts"
    return 0
  fi
  ts="$(TZ=IST-5:30 date '+%Y-%m-%d %H:%M:%S IST' 2>/dev/null)" || ts=""
  off="$(TZ=IST-5:30 date '+%z' 2>/dev/null)" || off=""
  if [ "$off" = "+0530" ] && [ -n "$ts" ]; then
    printf '%s' "$ts"
    return 0
  fi
  date -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || printf '%s' "unknown-time"
}

log() { # log LEVEL MESSAGE
  printf '[%s] [%s] %s\n' "$(ist_now)" "$1" "$2" >>"$LOG_FILE"
}

on_signal() {
  log INFO "shutdown: termination signal received, exiting cleanly"
  exit 0
}
trap on_signal INT TERM HUP

# The heartbeat state directory must exist and be writable before we start;
# otherwise every log write would silently (or noisily) fail.
if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
  printf 'vps-keepalive: cannot create state directory: %s\n' "$STATE_DIR" >&2
  exit 1
fi
if [ ! -w "$STATE_DIR" ]; then
  printf 'vps-keepalive: state directory is not writable: %s\n' "$STATE_DIR" >&2
  exit 1
fi
if [ -e "$LOG_FILE" ] && [ ! -w "$LOG_FILE" ]; then
  printf 'vps-keepalive: log file is not writable: %s\n' "$LOG_FILE" >&2
  exit 1
fi

run_beat() {
  local out rc
  out="$($HEARTBEAT_CMD 2>&1)"
  rc=$?
  # Keep log lines single-line and bounded regardless of command output.
  out="${out//$'\n'/ | }"
  out="${out//$'\r'/}"
  out="${out:0:160}"
  if [ "$rc" -eq 0 ]; then
    log INFO "heartbeat ok (exit 0): ${HEARTBEAT_CMD}${out:+ :: $out}"
  else
    # Ordinary command failures are logged and survived, never fatal.
    log WARN "heartbeat FAILED (exit $rc): ${HEARTBEAT_CMD}${out:+ :: $out}"
  fi
  return 0
}

log INFO "startup: pid=$$ interval=${INTERVAL}s beats=${BEATS}/interval (every ${STEP}s) command='${HEARTBEAT_CMD}' log=${LOG_FILE}"

# Heartbeat runs immediately once, then after every STEP seconds — with
# BEATS=1 that is exactly one beat per INTERVAL; higher BEATS spread more
# beats across the same window so at least one lands inside whatever
# sampling window the provider uses.
while :; do
  run_beat
  sleep "$STEP" &
  wait "$!" 2>/dev/null || true
done
