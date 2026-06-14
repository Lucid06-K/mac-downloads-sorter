#!/bin/bash
# Downloads Sorter — installer.
#
# Installs the auto-sorter for the CURRENT user (no sudo, nothing system-wide):
#   • copies the two scripts into ~/Library/Scripts
#   • builds two tiny helper apps so macOS can grant the needed permissions
#       - OrganizeDownloads.app  → holds the "access your Downloads folder" grant
#       - DownloadsNotifier.app  → posts the "Downloads sorted" notifications
#   • installs a per-user launch agent that runs it automatically
#   • walks you through the two permission prompts macOS will show
#
# Safe to re-run: it updates the scripts and keeps the helper apps (so you are
# not asked for permissions again). Remove everything with ./uninstall.sh.
set -euo pipefail

LABEL="com.downloads-sorter.agent"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src"
SCRIPTS="$HOME/Library/Scripts"
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/$LABEL.plist"
SORTER="$SCRIPTS/organize_downloads.sh"
CTL="$SCRIPTS/downloads-sorter"
ORG_APP="$SCRIPTS/OrganizeDownloads.app"
NOTIFY_APP="$SCRIPTS/DownloadsNotifier.app"
UID_NUM="$(id -u)"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
info() { printf '  \033[2m• %s\033[0m\n' "$1"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$1"; }

[ "$(uname)" = "Darwin" ] || { echo "This tool is macOS-only."; exit 1; }
[ -f "$SRC/organize_downloads.sh" ] && [ -f "$SRC/downloads-sorter" ] || {
    echo "Can't find src/ next to this installer. Run it from the cloned repo."; exit 1; }

bold "Downloads Sorter — installing for $(whoami)"

# 1) scripts ----------------------------------------------------------------
mkdir -p "$SCRIPTS" "$AGENTS" "$HOME/Library/Logs"
install -m 0755 "$SRC/organize_downloads.sh" "$SORTER"
install -m 0755 "$SRC/downloads-sorter" "$CTL"
ok "Installed scripts into ~/Library/Scripts"

# 2) helper apps (built fresh so they get THIS Mac's permission grants) ------
# macOS ties privacy permissions to an app's identity, so these must be built
# locally — they cannot be shipped pre-granted.
if [ ! -d "$ORG_APP" ]; then
    osacompile -o "$ORG_APP" -e "do shell script \"exec '$SORTER'\""
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.downloads-sorter.organizer" \
        "$ORG_APP/Contents/Info.plist" 2>/dev/null || true
    codesign --force --sign - "$ORG_APP" 2>/dev/null || true
    ok "Built OrganizeDownloads.app (Downloads access)"
else
    info "OrganizeDownloads.app already present — keeping it (preserves its permission)"
fi

if [ ! -d "$NOTIFY_APP" ]; then
    TMP_AS="$(mktemp -t dnotify).applescript"
    cat > "$TMP_AS" <<'AS'
on run argv
    try
        display notification (item 1 of argv) with title (item 2 of argv)
    on error
        display notification "Downloads sorted"
    end try
end run
AS
    osacompile -o "$NOTIFY_APP" "$TMP_AS"; rm -f "$TMP_AS"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.downloads-sorter.notifier" \
        "$NOTIFY_APP/Contents/Info.plist" 2>/dev/null || true
    codesign --force --sign - "$NOTIFY_APP" 2>/dev/null || true
    ok "Built DownloadsNotifier.app (notifications)"
else
    info "DownloadsNotifier.app already present — keeping it (preserves its permission)"
fi

# 3) launch agent (paths templated to THIS user) ----------------------------
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$ORG_APP/Contents/MacOS/applet</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$HOME/Downloads</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLIST
ok "Installed launch agent"

# the control script finds the agent by this label
if ! grep -q "$LABEL" "$CTL" 2>/dev/null; then
    info "Note: control script expects label '$LABEL'."
fi

# 4) load it ----------------------------------------------------------------
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null || true
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
ok "Loaded and enabled the sorter"

# 5) convenience alias ------------------------------------------------------
RC=""
case "${SHELL##*/}" in zsh) RC="$HOME/.zshrc" ;; bash) RC="$HOME/.bashrc" ;; esac
if [ -n "$RC" ] && ! grep -q "alias downloads-sorter=" "$RC" 2>/dev/null; then
    printf '\nalias downloads-sorter="%s"\n' "$CTL" >> "$RC"
    ok "Added 'downloads-sorter' alias to ${RC/#$HOME/~} (restart your shell to use it)"
fi

# 6) permission prompts -----------------------------------------------------
echo
bold "One-time permissions — macOS will now ask twice. Please click Allow on both:"
info "1) Files & Folders → access to your Downloads folder (so it can sort)"
info "2) Notifications → so it can tell you what it sorted"
echo
# trigger the notification permission prompt
"$NOTIFY_APP/Contents/MacOS/applet" "Downloads Sorter is installed 🎉" "Downloads Sorter" >/dev/null 2>&1 || true
# launch the organizer interactively so the Downloads-access prompt appears
open "$ORG_APP" 2>/dev/null || true
sleep 1

echo
bold "Done."
info "If you didn't see the Downloads prompt, drop a test file in ~/Downloads and run:"
info "    \"$CTL\" run     (or just: downloads-sorter run)"
info "Open the menu any time with:  downloads-sorter        (or: \"$CTL\")"
info "Full guide:  downloads-sorter  → Help & guide"
info "Uninstall:   ./uninstall.sh"
