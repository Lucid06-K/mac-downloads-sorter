#!/bin/bash
# Copyright 2026 Lucid06-K
# SPDX-License-Identifier: Apache-2.0
#
# Downloads Sorter — uninstaller. Removes the tool, its helper apps, the launch
# agent, and its settings. Your ~/Downloads folders and files are NOT touched.
set -uo pipefail

LABEL="com.downloads-sorter.agent"
SCRIPTS="$HOME/Library/Scripts"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

echo "Removing Downloads Sorter…"
echo "(your sorted files and folders in ~/Downloads are left exactly as they are)"

launchctl bootout  "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl disable  "gui/$UID_NUM/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$SCRIPTS/OrganizeDownloads.app" "$SCRIPTS/DownloadsNotifier.app"
rm -f  "$SCRIPTS/organize_downloads.sh" "$SCRIPTS/downloads-sorter"
rm -f  "$SCRIPTS"/organize_downloads.nonotify \
       "$SCRIPTS"/organize_downloads.cleannames \
       "$SCRIPTS"/organize_downloads.noaging \
       "$SCRIPTS"/organize_downloads.noduplicates \
       "$SCRIPTS"/organize_downloads.largefilegb \
       "$SCRIPTS"/organize_downloads.archivedays \
       "$SCRIPTS"/organize_downloads.metanames \
       "$SCRIPTS"/organize_downloads.autounzip \
       "$SCRIPTS"/organize_downloads.noscreenshotdate \
       "$SCRIPTS"/organize_downloads.lastrun \
       "$SCRIPTS"/organize_downloads.lastrun.partial \
       "$SCRIPTS"/organize_downloads.lastrun.undone \
       "$SCRIPTS"/.organize_downloads.aging_last 2>/dev/null

echo "Done. Removed scripts, helper apps, launch agent, and settings."
echo "If you added the alias, delete the 'alias downloads-sorter=' line from your ~/.zshrc or ~/.bashrc."
echo "You may also clear the leftover Privacy entries under System Settings → Privacy & Security."
