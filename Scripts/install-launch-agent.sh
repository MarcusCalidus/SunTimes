#!/bin/bash
# Installs (or with --uninstall removes) a per-user launchd agent that runs
# Scripts/resign-to-watch.sh every few hours. The script itself skips runs
# until ~20h have passed since the last successful install, so the app is
# refreshed about once a day and retried automatically if the watch was
# unreachable.
#
# macOS blocks background processes without an app from reaching devices on
# the local network (Local Network privacy), so the agent does not run the
# script directly: it opens a small helper app that runs it.
#
# Keep the repository outside ~/Documents, ~/Desktop and ~/Downloads; launchd
# jobs are not allowed to read those folders.
set -euo pipefail

LABEL="suntimes.auto-resign"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/SunTimes"
LOG="$LOG_DIR/auto-resign.log"
HELPER="$HOME/Library/Application Support/SunTimes/SunTimes Auto-Resign.app"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/resign-to-watch.sh"
INTERVAL_SECONDS="${SUNTIMES_CHECK_INTERVAL_SECONDS:-10800}"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -f "$PLIST"
  rm -rf "$HELPER"
  echo "Removed $LABEL."
  exit 0
fi

case "$SCRIPT" in
  "$HOME"/Documents/*|"$HOME"/Desktop/*|"$HOME"/Downloads/*)
    echo "warning: launchd jobs cannot read $SCRIPT; move the repository elsewhere (e.g. ~/Developer)." >&2 ;;
esac

chmod +x "$SCRIPT"
mkdir -p "$LOG_DIR" "$(dirname "$PLIST")" "$(dirname "$HELPER")"

# Helper app: runs the script, appending its output to the log.
rm -rf "$HELPER"
osacompile -o "$HELPER" -e "do shell script \"/bin/bash \" & quoted form of \"$SCRIPT\" & \" >> \" & quoted form of \"$LOG\" & \" 2>&1 || true\""
# No Dock icon; re-sign ad hoc after editing Info.plist.
plutil -replace LSUIElement -bool true "$HELPER/Contents/Info.plist"
codesign --force --sign - "$HELPER" 2>/dev/null

cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-W</string>
		<string>-g</string>
		<string>$HELPER</string>
	</array>
	<key>StartInterval</key>
	<integer>$INTERVAL_SECONDS</integer>
	<key>RunAtLoad</key>
	<true/>
	<key>ProcessType</key>
	<string>Background</string>
	<key>StandardOutPath</key>
	<string>$LOG</string>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $LABEL (checks every $((INTERVAL_SECONDS / 3600))h)."
echo "Log: $LOG"
