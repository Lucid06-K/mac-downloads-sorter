#!/bin/bash
# Copyright 2026 Lucid06-K
# SPDX-License-Identifier: Apache-2.0
#
# Downloads Sorter — uninstaller. Removes the tool, its helper apps, the launch
# agent, and its settings. Your ~/Downloads folders and files are NOT touched.
set -uo pipefail

LABEL="com.downloads-sorter.agent"
LEGACY_LABELS="com.tonnam.organize-downloads"
SCRIPTS="$HOME/Library/Scripts"
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/$LABEL.plist"
UID_NUM="$(id -u)"

echo "Removing Downloads Sorter…"
echo "(your sorted files and folders in ~/Downloads are left exactly as they are)"

# tear down the current label, any known legacy labels, and any other plist that
# runs our organizer app (so a legacy install isn't left as a broken zombie agent
# still loaded after its applet is deleted below).
for _lbl in "$LABEL" $LEGACY_LABELS; do
    launchctl bootout "gui/$UID_NUM/$_lbl" 2>/dev/null || true
    launchctl disable "gui/$UID_NUM/$_lbl" 2>/dev/null || true
    rm -f "$AGENTS/$_lbl.plist"
done
for _p in "$AGENTS"/*.plist; do
    [ -f "$_p" ] || continue
    grep -q 'OrganizeDownloads.app/Contents/MacOS/applet' "$_p" 2>/dev/null || continue
    _lbl="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$_p" 2>/dev/null || true)"
    [ -n "$_lbl" ] && { launchctl bootout "gui/$UID_NUM/$_lbl" 2>/dev/null || true; launchctl disable "gui/$UID_NUM/$_lbl" 2>/dev/null || true; }
    rm -f "$_p"
done

rm -rf "$SCRIPTS/OrganizeDownloads.app" "$SCRIPTS/DownloadsNotifier.app"
rm -f  "$SCRIPTS/downloads-sorter" "$SCRIPTS/downloads-sorter.bak"
# remove the whole settings/state family by prefix (the enumerated list drifted and
# left ~a dozen newer config files behind, which then silently reapplied on reinstall)
rm -f  "$SCRIPTS"/organize_downloads.* "$SCRIPTS"/.organize_downloads.* 2>/dev/null

echo "Done. Removed scripts, helper apps, launch agent(s), and settings."
echo "If you added the alias, delete the 'alias dsort=' line from your ~/.zshrc or ~/.bashrc."
echo "You may also clear the leftover Privacy entries under System Settings → Privacy & Security."
