# Changelog

All notable changes to vps-keepalive are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/) · [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-24

### Added
- **Real-work mode**: `vps-keepalive-workload` script — one burst of genuine
  CPU + disk activity (random data generation, gzip -9 compression, SHA-256
  hashing, forced `sync`), fully local, no network requests. Enable with
  `VPS_KEEPALIVE_CMD=workload`; tune with `VPS_KEEPALIVE_WORKLOAD_MB`
  (default 16).
- **Multiple beats per interval**: `VPS_KEEPALIVE_BEATS` splits the interval
  into evenly spaced beats — e.g. `VPS_KEEPALIVE_INTERVAL=1800` with
  `VPS_KEEPALIVE_BEATS=5` runs one beat every 6 minutes, so at least one
  lands inside a provider's sampling window.
- `vps-keepalive workload` subcommand to run one burst interactively.

### Fixed
- `VPS_KEEPALIVE_CMD`, `VPS_KEEPALIVE_BEATS` and `VPS_KEEPALIVE_WORKLOAD_MB`
  are now forwarded into the tmux session environment explicitly.

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
