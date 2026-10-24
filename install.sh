#!/usr/bin/env bash
# install.sh — one-command installer for vps-keepalive.
#
# Local (recommended — no network needed):
#   git clone https://github.com/ayusharyaneth/vps-keepalive.git
#   cd vps-keepalive && ./install.sh
#
# Remote one-liner:
#   curl -fsSL https://raw.githubusercontent.com/ayusharyaneth/vps-keepalive/main/install.sh | bash
#   VPS_KEEPALIVE_REPO=<owner>/<repo> bash install.sh      # fork/other repo
#
# The installer never needs root: everything lives under your home directory
# (~/.local/bin and ~/.local/state/vps-keepalive).
#
# Options:
#   --repo owner/name   GitHub repository to download when not run from a checkout
#   --branch NAME       Branch/tag to download (default: main)
#   --start             Start the heartbeat immediately after installing
#   -h, --help          Show this help
set -euo pipefail

REPO="${VPS_KEEPALIVE_REPO:-}"
BRANCH="main"
AUTO_START=0

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --start)  AUTO_START=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

info() { printf '%s\n' "$*"; }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

SRC=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/heartbeat.sh" ] && [ -f "$SCRIPT_DIR/vps-keepalive" ]; then
  SRC="$SCRIPT_DIR"
  info "Installing from local checkout: $SRC"
else
  # Piped (curl | bash) or moved away from its checkout: download a tarball.
  [ -n "$REPO" ] || REPO="${VPS_KEEPALIVE_REPO_DEFAULT:-}"
  if [ -z "$REPO" ]; then
    die "This copy of install.sh is not running from a repository checkout.
Either run it from a cloned vps-keepalive directory, or specify the repo:
    VPS_KEEPALIVE_REPO=<owner>/<repo> bash install.sh
    ./install.sh --repo <owner>/<repo>"
  fi
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  info "Downloading https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
  command -v curl >/dev/null 2>&1 || die "curl is required for remote installation."
  curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" | tar -xz -C "$TMP" --strip-components=1 \
    || die "download/extraction failed. Check the repo name ('${REPO}') and branch ('${BRANCH}')."
  if [ ! -f "$TMP/heartbeat.sh" ] || [ ! -f "$TMP/vps-keepalive" ]; then
    die "downloaded archive does not look like vps-keepalive."
  fi
  SRC="$TMP"
fi

# The manager's `install` command copies everything it needs from its own
# directory, so run it straight from the source tree.
bash "$SRC/vps-keepalive" install

BIN_DIR="${VPS_KEEPALIVE_BIN_DIR:-${HOME}/.local/bin}"
info ""
info "Done. Common commands:"
info "  ${BIN_DIR}/vps-keepalive start     # start the heartbeat"
info "  ${BIN_DIR}/vps-keepalive status    # is it running?"
info "  ${BIN_DIR}/vps-keepalive logs      # recent activity"
info "  ${BIN_DIR}/vps-keepalive stop      # stop it"

if [ "$AUTO_START" -eq 1 ]; then
  info ""
  bash "$SRC/vps-keepalive" start
fi
