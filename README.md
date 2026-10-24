<div align="center">

# vps-keepalive

**A lightweight, root-free keep-alive heartbeat for Linux VPSes.**

Runs a harmless command (`uptime` by default) immediately at startup and every
20 minutes, inside a persistent `tmux` session, with timestamped logging in
Indian Standard Time.

[![CI](https://github.com/ayusharyaneth/vps-keepalive/actions/workflows/ci.yml/badge.svg)](https://github.com/ayusharyaneth/vps-keepalive/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/tag/ayusharyaneth/vps-keepalive?label=release&sort=semver)](https://github.com/ayusharyaneth/vps-keepalive/releases)
![Shell](https://img.shields.io/badge/bash-4%2B-green)
![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS-lightgrey)

</div>

---

## ⚠️ What this tool can and cannot do

Read this before relying on it.

- ✅ **What it does:** generates regular activity *inside your VPS* — a
  terminal command runs on schedule, survives SSH disconnects, and writes a
  timestamped log you can inspect.
- ❌ **What it does not do:** it does **not** guarantee your provider will
  treat the VPS as active. Many providers detect idleness at the
  hypervisor/control-plane level (CPU, network, console logins), which a local
  `uptime` command may not influence at all. Effectiveness depends entirely on
  your provider's suspension policy.
- 💡 **Recommendation:** if your provider offers an official keep-alive,
  anti-hibernation, or suspension-opt-out option, use that first. Treat
  vps-keepalive as a best-effort supplement, not a guarantee.
- 📌 **Meaning of "running":** everywhere in this README and in the `status`
  command, *running* means the **local heartbeat process is alive** — never a
  verification that provider-side suspension has been prevented.

No credentials required. No network requests. Nothing is ever downloaded and
executed automatically.

## Contents

- [How it works](#how-it-works)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Multiple VPSes](#multiple-vpses)
- [Updating](#updating)
- [Uninstall](#uninstall)
- [Running without tmux](#running-without-tmux)
- [Troubleshooting](#troubleshooting)
- [Testing & CI](#testing--ci)
- [Versioning & releases](#versioning--releases)
- [License](#license)

## How it works

```text
SSH session                 tmux server (persists after SSH drops)
┌──────────────┐            ┌─────────────────────────────────────┐
│  you         │            │  session: vps-keepalive             │
│  ssh vps ────┼──detach───▶│  └─ heartbeat.sh                    │
└──────────────┘            │       ├─ run `uptime` immediately     │
                            │       ├─ sleep 1200s                │
                            │       └─ repeat, logging to:        │
                            │          ~/.local/state/vps-keepalive/heartbeat.log
                            └─────────────────────────────────────┘
```

## Features

- **Zero-config heartbeat** — `uptime` runs immediately at startup, then every
  1200 seconds; interval and command are configurable.
- **Survives SSH disconnects** — runs detached in a named `tmux` session.
- **IST timestamps** — all log lines use Asia/Kolkata (UTC+05:30, no DST),
  with a verified portable fallback when the timezone database is missing.
- **Full lifecycle logging** — startup, successful beats, failed beats
  (logged as warnings and *survived*, never fatal), and clean shutdown on
  `SIGINT`/`SIGTERM`/`SIGHUP`, appended to
  `~/.local/state/vps-keepalive/heartbeat.log`.
- **Safe operations** — duplicate-start protection, automatic stale-session
  and orphaned-process recovery, idempotent install/uninstall, nothing
  destructive.
- **Root-free by design** — installs entirely under your home directory;
  never asks for sudo.
- **Portable** — no hardcoded usernames, IPs, or paths; the same repository
  works on any number of machines.
- **Tested** — 49-check portable suite, Bats suite, end-to-end tests against
  **real tmux**, and ShellCheck, all enforced by GitHub Actions CI.

## Prerequisites

- Any Linux (or macOS/BSD) system with **Bash 4+**.
- [`tmux`](https://github.com/tmux/tmux) — required for the heartbeat to
  survive SSH disconnection.

Check whether tmux is available:

```bash
command -v tmux && tmux -V
```

**Install tmux on Ubuntu/Debian (with sudo):**

```bash
sudo apt update && sudo apt install -y tmux
```

**Without sudo access** — pick one:

1. Ask your VPS administrator to install tmux for you.
2. Place a statically linked `tmux` binary in `~/.local/bin`, run
   `chmod +x ~/.local/bin/tmux`, and ensure `~/.local/bin` is on your `PATH`.
   No root needed.
3. Use a user-space package manager such as Homebrew on Linux or Nix.

## Installation

### Option A — one command (remote)

```bash
curl -fsSL https://raw.githubusercontent.com/ayusharyaneth/vps-keepalive/main/install.sh | bash
```

### Option B — clone and install (recommended)

```bash
git clone https://github.com/ayusharyaneth/vps-keepalive.git
cd vps-keepalive
./install.sh            # add --start to begin the heartbeat immediately
```

Both options install to your home directory (no root, no prompts):

| Path | Purpose |
| --- | --- |
| `~/.local/bin/vps-keepalive` | Management script |
| `~/.local/bin/vps-keepalive-heartbeat` | Heartbeat loop |
| `~/.local/state/vps-keepalive/heartbeat.log` | Append-only activity log |

> [!TIP]
> If `vps-keepalive: command not found` appears after installing,
> `~/.local/bin` is not on your `PATH`. See
> [Troubleshooting](#troubleshooting).

### Option C — manual installation

```bash
mkdir -p ~/.local/bin ~/.local/state/vps-keepalive
cp heartbeat.sh ~/.local/bin/vps-keepalive-heartbeat
cp vps-keepalive ~/.local/bin/vps-keepalive
chmod +x ~/.local/bin/vps-keepalive ~/.local/bin/vps-keepalive-heartbeat
touch ~/.local/state/vps-keepalive/heartbeat.log
```

Make sure `~/.local/bin` is on your `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Usage

```bash
vps-keepalive start      # start the heartbeat (immediate beat + every 20 min)
vps-keepalive status     # is the tmux session up? is the heartbeat alive?
vps-keepalive logs       # last 50 log lines (logs -f to follow)
vps-keepalive attach     # watch the heartbeat tmux window (Ctrl-b d to detach)
vps-keepalive detach     # detach any attached clients
vps-keepalive restart    # stop + start
vps-keepalive stop       # stop everything
vps-keepalive uninstall  # remove scripts (logs kept; add --purge to delete)
```

All commands are idempotent: `start` twice will not create a second session,
and `stop` on a stopped system is a no-op. If a tmux session exists but the
heartbeat died, `start` replaces the stale session automatically.

<details>
<summary><strong>Example: <code>status</code> output</strong></summary>

```text
tmux session : running ('vps-keepalive')
heartbeat    : process alive
last log     : [2026-10-24 18:02:11 IST] [INFO] heartbeat ok (exit 0): uptime ::  18:02:11 up 3 days,  4:12,  1 user,  load average: 0.00, 0.01, 0.05

This confirms only that the LOCAL heartbeat process is running.
It does not verify that your provider counts the VPS as active;
suspension policies are provider-side. See README.md for details.
```

</details>

<details>
<summary><strong>Example: log file</strong></summary>

```text
[2026-10-24 18:02:11 IST] [INFO] startup: pid=4821 interval=1200s command='uptime' log=/home/deploy/.local/state/vps-keepalive/heartbeat.log
[2026-10-24 18:02:11 IST] [INFO] heartbeat ok (exit 0): uptime ::  18:02:11 up 3 days,  4:12,  1 user,  load average: 0.00, 0.01, 0.05
[2026-10-24 18:22:11 IST] [INFO] heartbeat ok (exit 0): uptime ::  18:22:11 up 3 days,  4:32,  1 user,  load average: 0.02, 0.01, 0.00
```

</details>

## Configuration

Everything is driven by environment variables — nothing is hardcoded.

| Variable | Default | Meaning |
| --- | --- | --- |
| `VPS_KEEPALIVE_INTERVAL` | `1200` | Seconds between beats (positive integer) |
| `VPS_KEEPALIVE_CMD` | `uptime` | The harmless command to run each beat |
| `VPS_KEEPALIVE_SESSION` | `vps-keepalive` | tmux session name |
| `VPS_KEEPALIVE_BIN_DIR` | `~/.local/bin` | Where scripts are installed |
| `VPS_KEEPALIVE_STATE_DIR` | `~/.local/state/vps-keepalive` | Where logs live |

To run a second, independent instance on the same machine:

```bash
VPS_KEEPALIVE_SESSION=vps-keepalive-second \
VPS_KEEPALIVE_STATE_DIR=~/.local/state/vps-keepalive-second \
  vps-keepalive start
```

## Multiple VPSes

There are no usernames, IPs, or paths baked in, so the same repository works
everywhere. On each new VPS:

```bash
ssh you@second-vps
sudo apt update && sudo apt install -y tmux   # if tmux is missing
git clone https://github.com/ayusharyaneth/vps-keepalive.git
cd vps-keepalive && ./install.sh --start
vps-keepalive status
```

## Updating

On any VPS where an older copy is installed:

```bash
cd vps-keepalive
git pull
./install.sh          # re-copies the updated scripts, keeps your logs
vps-keepalive restart # picks up the new heartbeat
```

The installer is idempotent and never touches your log file.

## Uninstall

```bash
vps-keepalive uninstall          # stops the heartbeat, removes scripts, keeps logs
vps-keepalive uninstall --purge  # also deletes ~/.local/state/vps-keepalive
```

## Running without tmux

You can start `~/.local/bin/vps-keepalive-heartbeat` directly (for example
under `nohup`), but it will likely be killed when your SSH session drops or
the VPS reboots. The `start`/`stop`/`attach` commands require tmux by design
because it is the only dependency-free way to keep a process alive after
disconnect. If tmux cannot be installed at all, consider a user-level
`systemd` service or a `@reboot` crontab entry as alternatives.

## Troubleshooting

**`Error: tmux is required but was not found in your PATH`**
Install tmux (see [Prerequisites](#prerequisites)). Without sudo, use the
static-binary or Homebrew/Nix route.

**`vps-keepalive: command not found`**
Two possible causes — check them in order:

1. **The installer hasn't run on this machine.** Verify with
   `ls -l ~/.local/bin/vps-keepalive`. If the file doesn't exist, install
   first: `cd ~/vps-keepalive && ./install.sh` (use `bash install.sh` if it
   says "Permission denied"), or use the remote one-liner from the
   [Installation](#installation) section.
2. **`~/.local/bin` is not on your `PATH`.** Add it and reload your shell:

   ```bash
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

If you'd rather not change `PATH`, call the script by full path instead:
`~/.local/bin/vps-keepalive start`.

Note that bash never picks up executables from your **current directory**:
running `vps-keepalive` from inside the cloned repo will always fail with
"command not found" until it is installed and on your `PATH`. From inside
the repo you can use `./vps-keepalive status` (note the `./`) even before
installing.

**`tmux session 'vps-keepalive' exited immediately`**
The heartbeat crashed before settling. Check `vps-keepalive logs`. Common
causes: the log directory is not writable, or `VPS_KEEPALIVE_INTERVAL` was set
to a non-numeric value.

**Log has `heartbeat FAILED (exit ...)` lines but the process keeps running**
That is by design: a failing heartbeat command is logged as a warning and the
loop continues. Check the command you set in `VPS_KEEPALIVE_CMD`.

**Session disappeared after the VPS rebooted**
tmux does not survive reboots. Log back in and run `vps-keepalive start`. If
you want automatic recovery, add `@reboot $HOME/.local/bin/vps-keepalive start`
to your crontab (`crontab -e`) — that is a cron job on your own box, not a
network request.

**Log timestamps show UTC instead of IST**
Your system lacks the tzdata database; the heartbeat automatically falls back
to a fixed UTC+05:30 offset (still labelled IST). Install `tzdata` via your
package manager to use the named zone.

**Permissions errors on the log directory**
Ensure `~/.local/state/vps-keepalive` is owned by your user:
`mkdir -p ~/.local/state/vps-keepalive && chown -R "$(id -u):$(id -g)" ~/.local/state`.

**How do I verify it survived an SSH disconnect?**
Disconnect, wait, reconnect, then run `vps-keepalive status` and
`vps-keepalive logs`. Beats should continue at the configured interval with
your session attached to nothing.

## Testing & CI

```bash
./tests/run_tests.sh   # portable: syntax, ShellCheck (if installed), full mock-tmux flow
bats tests             # Bats suite: mock-tmux, heartbeat, and real-tmux tests
```

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and pull
request:

- **ShellCheck** over all scripts, including the test suite.
- **Bats** suites with a mock tmux, plus end-to-end tests against **real tmux**
  on the runner.
- The portable suite, which also runs on machines without tmux.

## Versioning & releases

- Versions follow [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.
- The version lives in the `VERSION` variable at the top of the `vps-keepalive`
  script; update it in the same commit as the change.
- Record user-visible changes in [`CHANGELOG.md`](CHANGELOG.md).

Release checklist:

```bash
# 1. Update VERSION in the vps-keepalive script and add a CHANGELOG entry.
# 2. Commit, tag, and push:
git add -A
git commit -m "Release vX.Y.Z"
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin main --follow-tags
# 3. On GitHub: Releases → Draft a new release → pick the tag → publish.
```

## Contributing

Issues and pull requests are welcome. Please run `./tests/run_tests.sh` and
ShellCheck locally before submitting; CI will enforce both.

## License

[MIT](LICENSE) — free to use, modify, and redistribute.
