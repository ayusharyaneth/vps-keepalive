# Changelog

All notable changes to vps-keepalive are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/) · [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-24

### Added
- Heartbeat loop (`heartbeat.sh`): harmless command (default `uptime`) runs
  immediately at startup and every 1200 seconds, with IST timestamps
  (Asia/Kolkata, UTC+05:30) and a portable fallback when tzdata is missing.
- Append-only log at `~/.local/state/vps-keepalive/heartbeat.log` covering
  startup, successful beats, failed beats (warnings, never fatal), and clean
  shutdown on SIGINT/SIGTERM/SIGHUP.
- Management script (`vps-keepalive`): `install`, `uninstall` (`--purge`),
  `start`, `stop`, `restart`, `status`, `logs [N|-f]`, `attach`, `detach`,
  `version`, `help`.
- Persistent tmux session `vps-keepalive` with duplicate-start protection and
  stale-session recovery.
- One-command installer (`install.sh`) supporting local checkouts and remote
  `curl | bash` use; everything installs under the user's home directory with
  no root required.
- Portable bash test suite (`tests/run_tests.sh`, tmux mocked), Bats suite for
  mock and real-tmux coverage, and a GitHub Actions CI workflow with
  ShellCheck.
