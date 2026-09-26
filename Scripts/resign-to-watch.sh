#!/bin/bash
# Rebuilds, re-signs and re-installs SunTimes on a paired Apple Watch.
#
# Apps signed with a free (personal team) certificate expire after 7 days.
# Running this regularly (see Scripts/install-launch-agent.sh) keeps the app alive.
#
# Configuration is read from .env in the project root (copy .env.example), or
# from the file given in SUNTIMES_ENV_FILE:
#   SUNTIMES_WATCH_ID   required  watch UDID or CoreDevice identifier
#                                 (see: xcrun devicectl list devices)
#   SUNTIMES_TEAM_ID    optional  Apple Developer team ID; auto-detected from the
#                                 "Apple Development" certificate in the keychain
#
# Usage: Scripts/resign-to-watch.sh [--force]
#   Skips the run if the last successful install is less than
#   SUNTIMES_MIN_INTERVAL_HOURS (default 20) old, unless --force is given.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${SUNTIMES_ENV_FILE:-$REPO_DIR/.env}"
STATE_DIR="$HOME/Library/Application Support/SunTimes"
WORK_DIR="$HOME/Library/Caches/SunTimes/auto-resign"
STAMP="$STATE_DIR/last-install"
LOCK="$STATE_DIR/resign.lock"

# launchd starts jobs with a minimal PATH; Homebrew is needed for xcodegen.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# Use full Xcode even if xcode-select points at the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
  osascript -e "display notification \"$1\" with title \"SunTimes re-sign\"" >/dev/null 2>&1 || true
}

# Reads KEY=value from the env file without sourcing it.
env_value() {
  [[ -f "$ENV_FILE" ]] || return 0
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$1[[:space:]]*=[[:space:]]*//p" "$ENV_FILE" \
    | tail -n 1 | sed -E "s/[[:space:]]+#.*$//; s/^[\"'](.*)[\"'][[:space:]]*$/\1/"
}

detect_team_id() {
  security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | awk -v cmd="openssl x509 -noout -subject -nameopt multiline" '
        /BEGIN CERT/ { pem = "" }
        { pem = pem $0 "\n" }
        /END CERT/ { printf "%s", pem | cmd; close(cmd) }' \
    | sed -nE 's/^[[:space:]]*organizationalUnitName[[:space:]]*=[[:space:]]*//p' \
    | sort -u
}

fail() {
  log "ERROR: $*"
  # Only nag once the app is getting close to expiring.
  local age_days=99
  if [[ -f "$STAMP" ]]; then
    age_days=$(( ($(date +%s) - $(stat -f %m "$STAMP")) / 86400 ))
  fi
  if (( age_days >= 5 )); then
    notify "Re-install failed (last success ${age_days}d ago): $*"
  fi
  exit 1
}

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "$STATE_DIR" "$WORK_DIR"

if ! mkdir "$LOCK" 2>/dev/null; then
  log "Another run is in progress; exiting."
  exit 0
fi
trap 'rmdir "$LOCK"' EXIT

MIN_HOURS="${SUNTIMES_MIN_INTERVAL_HOURS:-$(env_value SUNTIMES_MIN_INTERVAL_HOURS)}"
MIN_HOURS="${MIN_HOURS:-20}"
if (( FORCE == 0 )) && [[ -f "$STAMP" ]]; then
  age_hours=$(( ($(date +%s) - $(stat -f %m "$STAMP")) / 3600 ))
  if (( age_hours < MIN_HOURS )); then
    log "Last install ${age_hours}h ago (< ${MIN_HOURS}h); nothing to do."
    exit 0
  fi
fi

WATCH_ID="${SUNTIMES_WATCH_ID:-$(env_value SUNTIMES_WATCH_ID)}"
[[ -n "$WATCH_ID" ]] || fail "SUNTIMES_WATCH_ID is not set in $ENV_FILE"

TEAM_ID="${SUNTIMES_TEAM_ID:-$(env_value SUNTIMES_TEAM_ID)}"
if [[ -z "$TEAM_ID" ]]; then
  teams="$(detect_team_id)"
  [[ -n "$teams" ]] || fail "No Apple Development certificate found; set SUNTIMES_TEAM_ID"
  (( $(wc -l <<<"$teams") == 1 )) || fail "Multiple teams found ($(echo $teams)); set SUNTIMES_TEAM_ID"
  TEAM_ID="$teams"
fi

command -v xcodegen >/dev/null || fail "xcodegen not found (brew install xcodegen)"

# Build from a private copy so the project you open in Xcode is left untouched.
SRC_DIR="$WORK_DIR/src"
log "Copying sources to $SRC_DIR"
rsync -a --delete --exclude .git --exclude .env --exclude '*.xcodeproj' --exclude DerivedData \
  "$REPO_DIR/" "$SRC_DIR/" || fail "Copying sources failed"
xcodegen generate --quiet --spec "$SRC_DIR/project.yml" || fail "xcodegen failed"

BUILD_DIR="$WORK_DIR/build"
rm -rf "$BUILD_DIR"

log "Building and signing (team from ${SUNTIMES_TEAM_ID:+env}${SUNTIMES_TEAM_ID:-keychain})"
xcodebuild \
  -project "$SRC_DIR/SunTimes.xcodeproj" \
  -target SunTimesWatch \
  -configuration Debug \
  -sdk watchos \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  ONLY_ACTIVE_ARCH=NO \
  SYMROOT="$BUILD_DIR/Products" \
  OBJROOT="$BUILD_DIR/Intermediates" \
  build -quiet || fail "xcodebuild failed"

APP="$(find "$BUILD_DIR/Products" -maxdepth 2 -name '*.app' -path '*-watchos/*' | head -n 1)"
[[ -n "$APP" ]] || fail "Built .app not found"

log "Installing $(basename "$APP") on watch"
xcrun devicectl device install app --device "$WATCH_ID" "$APP" \
  || fail "Install failed (is the watch unlocked and reachable?)"

touch "$STAMP"
log "Done."
