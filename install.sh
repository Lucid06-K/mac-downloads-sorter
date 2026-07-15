#!/bin/bash
# Copyright 2026 Lucid06-K
# SPDX-License-Identifier: Apache-2.0
#
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

# The applet receives the notification body/title via environment variables
# (DSORT_BODY / DSORT_TITLE). An osacompile applet's binary does NOT receive
# command-line argv, so the sorter passes the message through the environment;
# argv is kept only as a fallback for `osascript`-style invocation.
# Read the vars via `do shell script` (which decodes UTF-8), NOT `system
# attribute` (which reads raw bytes as MacRoman and mangles — ✓ and any
# non-ASCII filename into "‚Äî"-style artifacts).
NOTIFY_AS='on run argv
    set theTitle to "Downloads sorted"
    set theBody to ""
    try
        set theBody to (do shell script "printf \"%s\" \"$DSORT_BODY\"")
    end try
    try
        set tt to (do shell script "printf \"%s\" \"$DSORT_TITLE\"")
        if tt is not "" then set theTitle to tt
    end try
    if theBody is "" then
        try
            set theBody to (item 1 of argv)
            set theTitle to (item 2 of argv)
        end try
    end if
    if theBody is "" then set theBody to "Sorted your downloads"
    display notification theBody with title theTitle
end run'
if [ ! -d "$NOTIFY_APP" ]; then
    osacompile -o "$NOTIFY_APP" -e "$NOTIFY_AS"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.downloads-sorter.notifier" \
        "$NOTIFY_APP/Contents/Info.plist" 2>/dev/null || true
    codesign --force --sign - "$NOTIFY_APP" 2>/dev/null || true
    ok "Built DownloadsNotifier.app (notifications)"
elif ! osadecompile "$NOTIFY_APP/Contents/Resources/Scripts/main.scpt" 2>/dev/null | grep -q 'do shell script'; then
    # existing app has an old script — either it couldn't receive the message
    # body at all, or it read the env vars with `system attribute` (MacRoman
    # mojibake on any non-ASCII character). Refresh just the script in place,
    # keeping the bundle id so the macOS notification permission is preserved.
    TMP_SCPT="$(mktemp -d)/main.scpt"
    if osacompile -o "$TMP_SCPT" -e "$NOTIFY_AS" 2>/dev/null; then
        cp "$TMP_SCPT" "$NOTIFY_APP/Contents/Resources/Scripts/main.scpt"
        codesign --force --sign - "$NOTIFY_APP" 2>/dev/null || true
        ok "Refreshed DownloadsNotifier.app (fixes the notification text; permission kept)"
    fi
    rm -rf "$(dirname "$TMP_SCPT")"
else
    info "DownloadsNotifier.app already present and current — keeping it"
fi

# Both helpers are headless: mark them background-only (LSUIElement) so they
# don't appear in the Dock while running. Idempotent — bundles that already
# have the flag are left untouched. Patching an existing bundle changes its
# code hash, so macOS may re-ask once for that app's permission on next run.
hide_from_dock() {
    /usr/libexec/PlistBuddy -c "Print :LSUIElement" "$1/Contents/Info.plist" >/dev/null 2>&1 && return 0
    /usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$1/Contents/Info.plist" 2>/dev/null || return 0
    codesign --force --sign - "$1" 2>/dev/null || true
    ok "$(basename "$1") hidden from the Dock while it runs"
}
hide_from_dock "$ORG_APP"
hide_from_dock "$NOTIFY_APP"

# 2.5) migrate any prior install & preserve the user's schedule -------------
# Older installs (and pre-rename builds) used a different launchd label. If we
# ignore them we end up with TWO agents both watching ~/Downloads and racing on
# shared state, and `dsort off` on the new label wouldn't stop the old one.
LEGACY_LABELS="com.tonnam.organize-downloads"
INTERVAL_DEFAULT=43200
KEEP_INTERVAL="$INTERVAL_DEFAULT"
WAS_DISABLED=0

# read the currently-scheduled interval from any of our existing plists so a
# re-run (the documented `git pull && bash install.sh` update) doesn't silently
# reset a custom `dsort interval N`.
for _lbl in "$LABEL" $LEGACY_LABELS; do
    _p="$AGENTS/$_lbl.plist"
    [ -f "$_p" ] || continue
    _iv="$(/usr/libexec/PlistBuddy -c 'Print :StartInterval' "$_p" 2>/dev/null || true)"
    case "$_iv" in ''|*[!0-9]*) ;; *) KEEP_INTERVAL="$_iv"; break ;; esac
done
# also honour any plist we're about to migrate that runs OUR organizer app
for _p in "$AGENTS"/*.plist; do
    [ -f "$_p" ] || continue
    grep -q 'OrganizeDownloads.app/Contents/MacOS/applet' "$_p" 2>/dev/null || continue
    _iv="$(/usr/libexec/PlistBuddy -c 'Print :StartInterval' "$_p" 2>/dev/null || true)"
    case "$_iv" in ''|*[!0-9]*) ;; *) [ "$KEEP_INTERVAL" = "$INTERVAL_DEFAULT" ] && KEEP_INTERVAL="$_iv" ;; esac
done
# if the sorter was deliberately turned off (launchctl disable), don't silently re-enable it
if launchctl print-disabled "gui/$UID_NUM" 2>/dev/null | grep -qE "\"($LABEL|$(printf '%s' "$LEGACY_LABELS" | tr ' ' '|'))\" => (true|disabled)"; then
    WAS_DISABLED=1
fi

# tear down every prior agent of ours (known legacy labels + any plist that runs
# our organizer app under some other label) before installing the current one.
for _lbl in $LEGACY_LABELS; do
    launchctl bootout "gui/$UID_NUM/$_lbl" 2>/dev/null || true
    launchctl disable "gui/$UID_NUM/$_lbl" 2>/dev/null || true
    rm -f "$AGENTS/$_lbl.plist"
done
for _p in "$AGENTS"/*.plist; do
    [ -f "$_p" ] || continue
    [ "$_p" = "$PLIST" ] && continue
    grep -q 'OrganizeDownloads.app/Contents/MacOS/applet' "$_p" 2>/dev/null || continue
    _lbl="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$_p" 2>/dev/null || true)"
    [ -n "$_lbl" ] && { launchctl bootout "gui/$UID_NUM/$_lbl" 2>/dev/null || true; launchctl disable "gui/$UID_NUM/$_lbl" 2>/dev/null || true; }
    rm -f "$_p"
    info "Migrated an older sorter agent (${_lbl:-unknown}) → $LABEL"
done

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
    <integer>$KEEP_INTERVAL</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>2</integer>
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
if [ "$WAS_DISABLED" = 1 ]; then
    # respect a deliberate `dsort off`: install the plist but leave it disabled
    info "Sorter was turned off previously — leaving it off (turn on with: dsort on)"
else
    launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null || true
    launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    ok "Loaded and enabled the sorter (auto-run every $(( KEEP_INTERVAL / 3600 ))h)"
fi

# 5) convenience alias ------------------------------------------------------
# default to zsh's rc (macOS default shell); use bashrc only if login shell is bash
RC="$HOME/.zshrc"; case "${SHELL:-}" in */bash) RC="$HOME/.bashrc" ;; esac
touch "$RC" 2>/dev/null || true
RC_DISP="${RC/#$HOME/~}"
if grep -q 'alias dsort=' "$RC" 2>/dev/null; then
    info "'dsort' alias already present in $RC_DISP"
else
    printf '\n# Downloads Sorter — tidy ~/Downloads, open the menu + all commands\nalias dsort="%s"\n' "$CTL" >> "$RC"
    ok "Added 'dsort' alias to $RC_DISP"
fi

# 6) permission prompts -----------------------------------------------------
echo
bold "One-time permissions — macOS will now ask twice. Please click Allow on both:"
info "1) Files & Folders → access to your Downloads folder (so it can sort)"
info "2) Notifications → so it can tell you what it sorted"
echo
# trigger the notification permission prompt
DSORT_BODY="Downloads Sorter is installed 🎉" DSORT_TITLE="Downloads Sorter" "$NOTIFY_APP/Contents/MacOS/applet" >/dev/null 2>&1 || true
# launch the organizer interactively so the Downloads-access prompt appears
open "$ORG_APP" 2>/dev/null || true
sleep 1

echo
bold "Done."
echo
bold "Last step — load the 'dsort' command:   source $RC_DISP"
info "(or just open a new Terminal window). Then run:  dsort"
info "You can always run it directly without the alias:  \"$CTL\""
echo
info "If you didn't see the Downloads prompt, drop a file in ~/Downloads then run:  dsort run"
info "Full guide:  dsort  → Help & guide      Uninstall:  bash uninstall.sh"
