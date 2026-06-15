#!/bin/bash
# Copyright 2026 Lucid06-K
# SPDX-License-Identifier: Apache-2.0
#
# organize_downloads.sh — rule-based Downloads sorter, triggered by launchd.
#
# Phase 1: sorts loose files at the top of ~/Downloads into a nested category
#          structure (see classify() below).
# Phase 2: sweeps files older than ARCHIVE_DAYS out of the live category folders
#          into ~/Downloads/Archive/, mirroring the same structure.
#
# Never deletes or modifies files; only moves them (mv -n, never clobbers).
# Activity is logged to ~/Library/Logs/organize-downloads.log.
#
# launchd runs this via the OrganizeDownloads.app applet wrapper — macOS grants
# Downloads access (TCC) to the applet, not to bare /bin/bash. If the plist is
# ever pointed back at bash directly, sorting silently stops working.
#
# Structured to be sourceable: the run guard at the very bottom only fires main()
# when the script is executed directly, so helpers (e.g. the one-time migration)
# can `source` it to reuse classify()/move_to() without triggering a run.

DIR="$HOME/Downloads"
MIN_AGE=60           # seconds; skip files modified more recently (may still be downloading)
LOG="$HOME/Library/Logs/organize-downloads.log"
# Opt-in filename cleanup: OFF unless this flag file exists (mirrors .nonotify).
# Toggle with `downloads-sorter cleannames on|off`.
CLEANFLAG="$HOME/Library/Scripts/organize_downloads.cleannames"

# Files older than ARCHIVE_DAYS (by modified date) are swept into Archive/.
# Tunable via `downloads-sorter archivedays N` (stored in AGEFILE); default 30.
ARCHIVE_DAYS=30
AGEFILE="$HOME/Library/Scripts/organize_downloads.archivedays"
if [ -r "$AGEFILE" ]; then
    _ad=$(tr -dc '0-9' < "$AGEFILE" 2>/dev/null)
    [ -n "$_ad" ] && [ "$_ad" -ge 1 ] 2>/dev/null && ARCHIVE_DAYS=$_ad
fi

# Undo history. Each move is recorded as "old<TAB>new" to a .partial during the
# run; if the run did work, those lines are appended to HISTORY_FILE prefixed
# with a run stamp ("stamp<TAB>old<TAB>new"). The history is a stack: `dsort
# undo` reverts the most recent run and can be repeated to keep going back, and
# the menu can revert individual entries. Bounded so it never grows unbounded.
UNDO_FILE="$HOME/Library/Scripts/organize_downloads.lastrun"   # legacy (kept for one-time migration)
UNDO_PARTIAL="$UNDO_FILE.partial"
HISTORY_FILE="$HOME/Library/Scripts/organize_downloads.history"

# notification applet + mute flag (shared by notify() and the weekly aging nudge)
NOTIFIER="$HOME/Library/Scripts/DownloadsNotifier.app/Contents/MacOS/applet"
NONOTIFY_FLAG="$HOME/Library/Scripts/organize_downloads.nonotify"

# weekly "old stuff in Archive" nudge — never deletes; OFF while .noaging exists
AGING_DAYS=365
AGING_FLAG="$HOME/Library/Scripts/organize_downloads.noaging"
AGING_STAMP="$HOME/Library/Scripts/.organize_downloads.aging_last"

# duplicate detection: a byte-identical name-collision goes to Duplicates/ instead
# of "name (2)" so you can bulk-review. ON unless the flag exists.
DEDUP_FLAG="$HOME/Library/Scripts/organize_downloads.noduplicates"

# big-file quarantine: files >= this many GB go to Large Files/ for deliberate
# review (NOT auto-archived). 0 = off. Tunable via LFFILE; default 5 GB.
LARGEFILE_GB=5
LFFILE="$HOME/Library/Scripts/organize_downloads.largefilegb"
if [ -r "$LFFILE" ]; then
    _lf=$(tr -dc '0-9' < "$LFFILE" 2>/dev/null)
    [ -n "$_lf" ] && LARGEFILE_GB=$_lf
fi
LARGEFILE_BYTES=$(( LARGEFILE_GB * 1024 * 1024 * 1024 ))

# screenshot date-prefixing + month buckets (Screenshots/YYYY-MM/YYYY-MM-DD Screenshot.ext);
# ON unless the flag exists. metadata naming (PDF titles via mdls) is opt-in OFF.
SS_FLAG="$HOME/Library/Scripts/organize_downloads.noscreenshotdate"
META_FLAG="$HOME/Library/Scripts/organize_downloads.metanames"
# opt-in auto-unzip (OFF by default): expand .zip into a same-named subfolder.
AUTOUNZIP_FLAG="$HOME/Library/Scripts/organize_downloads.autounzip"

# user-defined rules in ~/.downloads-rules.conf — lines like "*statement* -> Documents/Finance"
# (arrow may be -> or →; # comments and blanks ignored). Loaded once; checked
# before the built-in rules so a user rule can override any category.
RULES_FILE="$HOME/.downloads-rules.conf"
RULE_PAT=(); RULE_DEST=()
if [ -r "$RULES_FILE" ]; then
    while IFS= read -r _rl || [ -n "$_rl" ]; do
        case "$_rl" in ''|'#'*) continue ;; esac
        _rl="${_rl//→/->}"
        case "$_rl" in *'->'*) ;; *) continue ;; esac
        _pat=$(printf '%s' "${_rl%%->*}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
        _dst=$(printf '%s' "${_rl#*->}"  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$_pat" ] && [ -n "$_dst" ] && { RULE_PAT+=("$_pat"); RULE_DEST+=("$_dst"); }
    done < "$RULES_FILE"
fi

# Scope filter (managed from the menu). Two optional lists, one entry per line —
# each entry is a category name (Media, Documents/PDFs…) or a bare extension (dmg):
#   .exclude — files matching these are left where they are (their folder is never created)
#   .only    — if non-empty, ONLY files matching these are sorted; the rest are left alone
EXCLUDE_FILE="$HOME/Library/Scripts/organize_downloads.exclude"
ONLY_FILE="$HOME/Library/Scripts/organize_downloads.only"
# _read_list <file> — echo trimmed, non-comment lines (no eval; values stay data)
_read_list() {
    [ -r "$1" ] || return 0
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
        case "$line" in ''|'#'*) continue ;; esac
        printf '%s\n' "$line"
    done < "$1"
}
EXCLUDE=(); while IFS= read -r _e; do EXCLUDE+=("$_e"); done < <(_read_list "$EXCLUDE_FILE")
ONLY=();    while IFS= read -r _e; do ONLY+=("$_e");    done < <(_read_list "$ONLY_FILE")

# _filter_match <ext> <rel> <entries…> -> 0 if (ext,rel) matches any list entry
# (bare extension match, or a category that equals/prefixes the destination)
_filter_match() {
    local ext="$1" rel="$2" e; shift 2
    for e in "$@"; do
        [ "$ext" = "$e" ] && return 0
        case "$rel" in "$e"|"$e"/*) return 0 ;; esac
    done
    return 1
}
# in_scope <ext> <rel> -> 0 if this file should be sorted, 1 to leave it alone
in_scope() {
    [ ${#ONLY[@]} -gt 0 ]    && { _filter_match "$1" "$2" "${ONLY[@]}"    || return 1; }
    [ ${#EXCLUDE[@]} -gt 0 ] && { _filter_match "$1" "$2" "${EXCLUDE[@]}" && return 1; }
    return 0
}

# Live category folders we manage. The archive sweep walks exactly these, so any
# folder you create yourself in Downloads is left completely untouched.
# NOTE: "Archive" is deliberately NOT listed — we never re-archive Archive.
MANAGED_DIRS=(
    "Screenshots" "Media" "Documents" "Compressed Files" "Installers & Apps"
    "Disk Images" "Code & Scripts" "Invoices & Receipts" "Design" "Fonts"
    "3D & CAD" "Torrents" "Data" "Calendars & Contacts" "Misc"
)

mkdir -p "$(dirname "$LOG")"
# single-generation rotation so the log never grows unbounded
[ -f "$LOG" ] && [ "$(stat -f %z "$LOG")" -gt 524288 ] && mv "$LOG" "$LOG.old"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# accumulated across passes, summarized in one notification at exit
MOVE_COUNT=0
ARCHIVE_COUNT=0
MOVES=""
SUMMARY=""           # newline-separated destination categories, for the grouped notification

# classify <basename> -> echoes the relative category path (may be nested, e.g.
# "Documents/PDFs"). Filename-keyword rules win over extension rules; first match
# wins. Extensions are matched case-insensitively.
classify() {
    local base="$1" lower ext i
    lower=$(echo "$base" | tr '[:upper:]' '[:lower:]')
    ext="${lower##*.}"

    # --- user-defined rules win (matched against the lowercased filename) ---
    for i in "${!RULE_PAT[@]}"; do
        case "$lower" in ${RULE_PAT[$i]}) echo "${RULE_DEST[$i]}"; return ;; esac
    done

    # --- filename-keyword rules (checked before extension) ---
    # "scr" only counts as a screenshot when followed by a separator/digit
    # (SCR-20260614…, SCR_… , SCR2026…) so it never grabs script.py / scratch.txt
    case "$lower" in
        screenshot*|"screen shot"*|"screen recording"*|scr[-_0-9]*) echo "Screenshots"; return ;;
    esac
    case "$lower" in
        *invoice*|*receipt*|*statement*|*billing*|*bill_*|*bill-*) echo "Invoices & Receipts"; return ;;
    esac

    # --- extension rules ---
    case "$ext" in
        png|jpg|jpeg|gif|heic|heif|webp|svg|tif|tiff|bmp|avif|ico)                       echo "Media/Images" ;;
        mp3|wav|m4a|m4b|flac|aac|ogg|opus|aiff|aif)                                     echo "Media/Audio" ;;
        mp4|mov|mkv|avi|m4v|webm|mpg|mpeg|wmv|flv|srt|vtt)                               echo "Media/Video" ;;

        pdf)                                                                            echo "Documents/PDFs" ;;
        ppt|pptx|pps|ppsx|key|odp)                                                      echo "Documents/Slides" ;;
        xls|xlsx|xlsm|csv|tsv|numbers|ods)                                              echo "Documents/Spreadsheets" ;;
        doc|docx|txt|md|markdown|rtf|rtfd|pages|odt|tex|bib|wpd)                         echo "Documents/Word & Text" ;;
        epub|mobi|azw|azw3|fb2|djvu)                                                    echo "Documents/eBooks" ;;
        html|htm|webarchive|mht|mhtml|webloc|url)                                       echo "Documents/Web" ;;

        zip|tar|gz|tgz|bz2|tbz|7z|rar|xz|zst|lz|lzma|cab|z)                             echo "Compressed Files" ;;
        dmg|iso|img|toast|cdr|vcd)                                                      echo "Disk Images" ;;
        pkg|mpkg|app|xip|msi|exe|deb|rpm|appimage|apk)                                  echo "Installers & Apps" ;;

        py|ipynb|sh|zsh|bash|js|mjs|cjs|ts|tsx|jsx|json|jsonl|yaml|yml|toml|xml|sql|css|scss|sass|less|c|cc|cpp|h|hpp|java|rb|go|rs|php|swift|kt|kts|scpt|applescript|plist|ini|cfg|conf|env|lua|pl) echo "Code & Scripts" ;;

        psd|ai|sketch|fig|xd|eps|indd|afdesign|afphoto|afpub)                           echo "Design" ;;
        ttf|otf|ttc|woff|woff2|fon|pfb|pfm)                                             echo "Fonts" ;;
        stl|obj|fbx|blend|3ds|dae|dwg|dxf|step|stp|igs|iges|gltf|glb|ply|usdz|3mf)      echo "3D & CAD" ;;
        torrent)                                                                        echo "Torrents" ;;
        sqlite|sqlite3|db|accdb|mdb|dat|parquet|avro)                                   echo "Data" ;;
        ics|ical|vcf|vcard)                                                             echo "Calendars & Contacts" ;;

        *)                                                                              echo "Misc" ;;
    esac
}

# clean_name <stem-without-extension> -> echoes a tidied stem.
# Conservative by design (a wrong rename is worse than a messy one):
#   - URL-decodes the common %20 escape
#   - removes long random hash/token blobs, but ONLY a whole alnum token of 20+
#     chars that mixes letters AND digits — so "Chapter_03_Glycolysis" (its
#     tokens are short) and pure numbers/years survive
#   - strips TRAILING duplicate/version markers (copy, v2 …) but leaves the same
#     words mid-name, so "Final Report" / "How to Copy Files" are untouched
#   - collapses repeated separators and trims edge junk
# Never returns an empty string.
clean_name() {
    local n="$1"
    n="${n//%20/ }"
    n=$(printf '%s' "$n" | /usr/bin/perl -pe '
        s/(?<![A-Za-z0-9])(?=[A-Za-z0-9]{20,})(?=[A-Za-z0-9]*[0-9])(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]+(?![A-Za-z0-9])//g;
        s/[ _-]+v[0-9]+(?=[ _-]*(\([0-9]+\))?$)//i;
        s/[ _-]+(final|copy|copies|duplicate)(?=[ _-]*(\([0-9]+\))?$)//i;
        s/[ _]{2,}/ /g;
        s/-{2,}/-/g;
        s/^[ ._-]+//;
        s/[ ._-]+$//;
        s/[ _-]+([)\]])/$1/g;
    ')
    [ -z "$n" ] && n="$1"
    printf '%s' "$n"
}

# clean_basename <basename> -> tidied basename with the extension preserved.
# Strips a trailing ?query first so the extension is detected correctly. We do
# NOT touch #fragments — "C# Notes" and "Track #1" are legitimate names.
clean_basename() {
    local b="$1" stem ext
    b="${b%%\?*}"
    if [[ "$b" == *.* ]]; then ext=".${b##*.}"; stem="${b%.*}"; else ext=""; stem="$b"; fi
    printf '%s%s' "$(clean_name "$stem")" "$ext"
}

dedup_on()      { [ ! -e "$DEDUP_FLAG" ]; }
screenshot_on() { [ ! -e "$SS_FLAG" ]; }
meta_on()       { [ -e "$META_FLAG" ]; }
autounzip_on()  { [ -e "$AUTOUNZIP_FLAG" ]; }

# try_unzip <zipfile> — expand a .zip into a unique same-named subfolder under
# Compressed Files/ (via macOS ditto), then keep the original archive there too.
# Guarded against zip bombs (skips if uncompressed > 5 GB). Contents are NOT
# re-sorted. Best-effort: any failure just files the archive normally.
try_unzip() {
    local zip="$1" base name dest total n d
    base=$(basename "$zip"); name="${base%.*}"
    total=$(unzip -l "$zip" 2>/dev/null | tail -1 | awk '{print $1}')
    case "$total" in ''|*[!0-9]*) total=0 ;; esac
    if [ "$total" -gt $((5 * 1024 * 1024 * 1024)) ]; then
        log "unzip skipped (>5GB uncompressed): $base"
        move_to "$zip" "Compressed Files"; return
    fi
    d="$DIR/Compressed Files/$name"; n=2
    while [ -e "$d" ]; do d="$DIR/Compressed Files/$name ($n)"; n=$((n+1)); done
    dest="$d"; mkdir -p "$dest"
    if ditto -x -k "$zip" "$dest" 2>>"$LOG"; then
        log "unzipped: $base -> Compressed Files/$(basename "$dest")/"
        MOVE_COUNT=$((MOVE_COUNT+1)); SUMMARY="${SUMMARY}Compressed Files (unzipped)"$'\n'
    else
        log "unzip failed: $base"; rmdir "$dest" 2>/dev/null
    fi
    move_to "$zip" "Compressed Files"
}

# screenshot_target <basename> <filepath> -> "Screenshots/YYYY-MM<TAB>YYYY-MM-DD Label.ext"
# Date comes from the filename if it carries a YYYY-MM-DD, else the file's mtime.
screenshot_target() {
    local base="$1" file="$2" lower date label ext
    lower=$(echo "$base" | tr '[:upper:]' '[:lower:]')
    ext="${base##*.}"; [ "$ext" = "$base" ] && ext="png"
    date=$(echo "$base" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    [ -z "$date" ] && date=$(stat -f %Sm -t %Y-%m-%d "$file" 2>/dev/null)
    case "$lower" in *"screen recording"*|*"screen-recording"*) label="Screen Recording" ;; *) label="Screenshot" ;; esac
    printf '%s\t%s' "Screenshots/${date%-*}" "$date $label.$ext"
}

# meta_rename <filepath> <basename> -> a tidied name from the PDF's embedded title,
# or the original basename unchanged. Conservative: only when the title is sane.
meta_rename() {
    local file="$1" base="$2" title ext stem clean
    ext="${base##*.}"
    title=$(mdls -name kMDItemTitle -raw "$file" 2>/dev/null)
    [ "$title" = "(null)" ] && title=""
    [ -z "$title" ] && { printf '%s' "$base"; return; }
    clean=$(printf '%s' "$title" | tr '/:' '  ' | tr -s ' ' | sed 's/^ *//; s/ *$//')
    stem="${base%.*}"
    [ ${#clean} -lt 3 ] && { printf '%s' "$base"; return; }
    [ ${#clean} -gt 80 ] && clean="${clean:0:80}"
    [ "$clean" = "$stem" ] && { printf '%s' "$base"; return; }
    printf '%s.%s' "$clean" "$ext"
}

# byte-identical? cheap size compare first, then sha (only when sizes match).
files_identical() {
    local sa sb
    sa=$(stat -f %z "$1" 2>/dev/null); sb=$(stat -f %z "$2" 2>/dev/null)
    [ -n "$sa" ] && [ "$sa" = "$sb" ] || return 1
    [ "$(shasum "$1" 2>/dev/null | cut -d' ' -f1)" = "$(shasum "$2" 2>/dev/null | cut -d' ' -f1)" ]
}

# move_to <file> <relative-dir> [verb]
# Moves <file> into $DIR/<relative-dir>, creating it as needed and never
# clobbering an existing file (appends " (2)", " (3)", … like Finder). A
# byte-identical name-collision is diverted to Duplicates/ instead.
# verb defaults to "moved"; pass "archived" for the Archive sweep so it counts
# and logs separately.
move_to() {
    local file="$1" reldir="$2" verb="${3:-moved}" forcename="${4:-}"
    local dest_dir="$DIR/$reldir"
    mkdir -p "$dest_dir"
    local base ext name target n cleaned
    base=$(basename "$file")
    if [ -n "$forcename" ]; then
        # caller supplied the final name (screenshot / metadata rename)
        [ "$forcename" != "$base" ] && log "renamed: $base -> $forcename"
        base="$forcename"
    elif [ -e "$CLEANFLAG" ]; then
        # opt-in filename cleanup, applied before the dedup below so it stays
        # collision-safe; every rewrite is logged for auditability/reversibility
        cleaned=$(clean_basename "$base")
        if [ -n "$cleaned" ] && [ "$cleaned" != "$base" ]; then
            log "renamed: $base -> $cleaned"
            base="$cleaned"
        fi
    fi
    target="$dest_dir/$base"
    if [ -e "$target" ]; then
        # byte-identical duplicate (only checked on a name clash) -> Duplicates/
        if [ "$verb" != "archived" ] && dedup_on && files_identical "$file" "$target"; then
            reldir="Duplicates"; dest_dir="$DIR/Duplicates"; verb="duplicate"
            mkdir -p "$dest_dir"; target="$dest_dir/$base"
        fi
        if [ -e "$target" ]; then                  # still need no-clobber naming
            ext="${base##*.}"
            if [ "$ext" = "$base" ]; then ext=""; name="$base"; else ext=".$ext"; name="${base%.*}"; fi
            n=2
            while [ -e "$dest_dir/$name ($n)$ext" ]; do n=$((n+1)); done
            target="$dest_dir/$name ($n)$ext"
        fi
    fi
    # -n + source-gone check: never clobber a file that appeared at the target
    # between the collision check and the move
    if mv -n "$file" "$target" 2>>"$LOG" && [ ! -e "$file" ]; then
        log "$verb: $base -> $reldir/"
        # record for undo (original absolute path <TAB> new absolute path)
        printf '%s\t%s\n' "$file" "$target" >> "$UNDO_PARTIAL" 2>/dev/null
        if [ "$verb" = "archived" ]; then
            ARCHIVE_COUNT=$((ARCHIVE_COUNT+1))
        else
            MOVE_COUNT=$((MOVE_COUNT+1))
            MOVES="${MOVES:+$MOVES, }$base -> $reldir"
            SUMMARY="${SUMMARY}${reldir}"$'\n'
        fi
    fi
}

# Phase 1: sort loose files sitting at the top level of Downloads.
scan() {
    YOUNG_SKIPPED=0
    WAIT=0
    local now f base ext mtime need rel sz ssrel ssname mname
    now=$(date +%s)
    shopt -s nullglob
    for f in "$DIR"/*; do
        [ -f "$f" ] || continue                       # files only; leave folders alone

        base=$(basename "$f")
        case "$base" in .*) continue ;; esac          # hidden files
        case "$base" in '~$'*) continue ;; esac       # MS Office lock files

        ext=$(echo "${base##*.}" | tr '[:upper:]' '[:lower:]')
        case "$ext" in                                # in-progress downloads
            crdownload|download|part|partial|tmp|opdownload|aria2|'!ut') continue ;;
        esac

        # too fresh — note it so we can wait it out and rescan before exiting
        mtime=$(stat -f %m "$f" 2>/dev/null) || continue
        if [ $((now - mtime)) -lt $MIN_AGE ]; then
            YOUNG_SKIPPED=1
            need=$((MIN_AGE - (now - mtime)))
            [ $need -gt $WAIT ] && WAIT=$need
            continue
        fi

        rel=$(classify "$base")
        # respect the user's exclude / only-sort filter — leave out-of-scope files put
        in_scope "$ext" "$rel" || continue

        # big-file quarantine overrides normal categorisation (parked for review)
        if [ "$LARGEFILE_BYTES" -gt 0 ]; then
            sz=$(stat -f %z "$f" 2>/dev/null)
            if [ -n "$sz" ] && [ "$sz" -ge "$LARGEFILE_BYTES" ]; then
                move_to "$f" "Large Files"
                continue
            fi
        fi
        # screenshots -> date-prefix + month bucket
        if [ "$rel" = "Screenshots" ] && screenshot_on; then
            IFS=$'\t' read -r ssrel ssname <<< "$(screenshot_target "$base" "$f")"
            move_to "$f" "$ssrel" moved "$ssname"
            continue
        fi
        # PDFs -> optional metadata-based rename (opt-in)
        if [ "$rel" = "Documents/PDFs" ] && meta_on; then
            mname=$(meta_rename "$f" "$base")
            if [ -n "$mname" ] && [ "$mname" != "$base" ]; then
                move_to "$f" "$rel" moved "$mname"
                continue
            fi
        fi
        # opt-in auto-unzip of .zip archives
        if [ "$rel" = "Compressed Files" ] && [ "$ext" = "zip" ] && autounzip_on; then
            try_unzip "$f"
            continue
        fi
        move_to "$f" "$rel"
    done
}

# Phase 2: sweep files older than ARCHIVE_DAYS out of the live category folders
# into Archive/, preserving each file's category path
# (Documents/PDFs/foo.pdf -> Archive/Documents/PDFs/foo.pdf). Because old files
# keep leaving the live tree, the live tree stays small and this stays cheap.
archive_old() {
    local cat f rel base
    for cat in "${MANAGED_DIRS[@]}"; do
        [ -d "$DIR/$cat" ] || continue
        # process substitution (not a pipe) so ARCHIVE_COUNT survives the loop
        while IFS= read -r -d '' f; do
            base=$(basename "$f")
            case "$base" in .*) continue ;; esac      # hidden
            case "$base" in '~$'*) continue ;; esac   # MS Office lock files — never archive junk
            rel=$(dirname "${f#"$DIR"/}")             # e.g. "Documents/PDFs"
            move_to "$f" "Archive/$rel" "archived"
        done < <(find "$DIR/$cat" -type f -mtime +"$ARCHIVE_DAYS" ! -name '.*' ! -name '~$*' -print0)
    done
}

# One notification per run, covering both phases; silenced while the flag file
# exists. Posted via the DownloadsNotifier applet — bare osascript under launchd
# has no bundle ID, so Notification Center drops it silently.
notify() {
    [ -e "$NONOTIFY_FLAG" ] && return
    [ "$MOVE_COUNT" -eq 0 ] && [ "$ARCHIVE_COUNT" -eq 0 ] && return

    # per-category rollup, e.g. "3 → Documents/PDFs, 2 → Media/Images"
    local rollup body
    rollup=$(printf '%s' "$SUMMARY" | sed '/^$/d' | sort | uniq -c | sort -rn | \
        awk '{ n=$1; $1=""; sub(/^[ \t]+/,""); printf "%s%d → %s", (NR>1?", ":""), n, $0 }')
    if [ "$MOVE_COUNT" -gt 0 ] && [ "$ARCHIVE_COUNT" -gt 0 ]; then
        body="$rollup · archived $ARCHIVE_COUNT old"
    elif [ "$MOVE_COUNT" -gt 0 ]; then
        body="$rollup"
    else
        body="Archived $ARCHIVE_COUNT file(s) older than ${ARCHIVE_DAYS}d"
    fi
    [ ${#body} -gt 160 ] && body="${body:0:157}..."
    "$NOTIFIER" "$body" "Downloads sorted" >/dev/null 2>>"$LOG"
}

# preview — dry run: print where each loose top-level file WOULD go (and, if
# cleanup is enabled, the tidied name) without moving anything. Used by
# `downloads-sorter preview`.
preview() {
    local f base ext rel cleaned now mtime tag count=0 sz
    now=$(date +%s)
    shopt -s nullglob
    for f in "$DIR"/*; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        case "$base" in .*) continue ;; esac
        case "$base" in '~$'*) continue ;; esac
        ext=$(echo "${base##*.}" | tr '[:upper:]' '[:lower:]')
        case "$ext" in crdownload|download|part|partial|tmp|opdownload|aria2|'!ut') continue ;; esac
        rel=$(classify "$base")
        if ! in_scope "$ext" "$rel"; then
            printf '%s\n    → (skipped — excluded by your filter)\n' "$base"
            count=$((count+1)); continue
        fi
        if [ "$LARGEFILE_BYTES" -gt 0 ]; then
            sz=$(stat -f %z "$f" 2>/dev/null)
            [ -n "$sz" ] && [ "$sz" -ge "$LARGEFILE_BYTES" ] && rel="Large Files"
        fi
        tag=""
        mtime=$(stat -f %m "$f" 2>/dev/null)
        [ -n "$mtime" ] && [ $((now - mtime)) -lt "$MIN_AGE" ] && tag="  [too fresh — will wait]"
        # reflect screenshot / metadata / cleanup renaming in the preview
        if [ "$rel" = "Screenshots" ] && screenshot_on; then
            IFS=$'\t' read -r rel cleaned <<< "$(screenshot_target "$base" "$f")"
        elif [ "$rel" = "Documents/PDFs" ] && meta_on; then
            cleaned=$(meta_rename "$f" "$base")
        elif [ -e "$CLEANFLAG" ]; then
            cleaned=$(clean_basename "$base")
        else
            cleaned="$base"
        fi
        # top line = current name; second line = destination/final name (+ any note)
        printf '%s\n    → %s/%s%s\n' "$base" "$rel" "$cleaned" "$tag"
        count=$((count+1))
    done
    [ "$count" -eq 0 ] && echo "(no loose files to sort)"
}

# prune_empty — keep the tree tidy as files move/age out. Conservative scope:
# every empty dir under Archive/ (sorter fully owns it) plus the sorter's OWN
# empty sub-buckets in the live tree. Never the category roots, never your folders.
prune_empty() {
    [ -d "$DIR/Archive" ] && find "$DIR/Archive" -mindepth 1 -type d -empty -delete 2>/dev/null
    local b
    for b in "Media/Images" "Media/Audio" "Media/Video" \
             "Documents/PDFs" "Documents/Slides" "Documents/Spreadsheets" \
             "Documents/Word & Text" "Documents/eBooks" "Documents/Web"; do
        [ -d "$DIR/$b" ] && rmdir "$DIR/$b" 2>/dev/null   # rmdir only succeeds when empty
    done
}

# aging_notice — at most weekly, nudge if Archive holds files older than a year.
# Never deletes anything. OFF while .noaging exists; respects the global mute.
aging_notice() {
    [ -e "$AGING_FLAG" ] && return
    [ -d "$DIR/Archive" ] || return
    if [ -f "$AGING_STAMP" ]; then
        local last now
        last=$(stat -f %m "$AGING_STAMP" 2>/dev/null || echo 0)
        now=$(date +%s)
        [ $((now - last)) -lt 604800 ] && return          # already nudged this week
    fi
    local old
    old=$(find "$DIR/Archive" -type f ! -name '.*' -mtime +"$AGING_DAYS" 2>/dev/null | wc -l | tr -d ' ')
    [ "${old:-0}" -gt 0 ] || return
    touch "$AGING_STAMP"                                   # mark the week regardless of mute
    [ -e "$NONOTIFY_FLAG" ] && return
    "$NOTIFIER" "$old file(s) in Archive over a year old — review?" "Downloads sorter" >/dev/null 2>>"$LOG"
}

# category_map — "Category|what routes there" for the Help "Folder categories"
# view. Display only; KEEP IN SYNC WITH classify() above.
category_map() {
    cat <<'EOF'
Screenshots|names starting with: screenshot, "screen shot", "screen recording", SCR-
Media/Images|png jpg jpeg gif heic heif webp svg tif tiff bmp avif ico
Media/Audio|mp3 wav m4a m4b flac aac ogg opus aiff aif
Media/Video|mp4 mov mkv avi m4v webm mpg mpeg wmv flv srt vtt
Documents/PDFs|pdf
Documents/Slides|ppt pptx pps ppsx key odp
Documents/Spreadsheets|xls xlsx xlsm csv tsv numbers ods
Documents/Word & Text|doc docx txt md markdown rtf rtfd pages odt tex bib wpd
Documents/eBooks|epub mobi azw azw3 fb2 djvu
Documents/Web|html htm webarchive mht mhtml webloc url
Compressed Files|zip tar gz tgz bz2 tbz 7z rar xz zst lz lzma cab z
Disk Images|dmg iso img toast cdr vcd
Installers & Apps|pkg mpkg app xip msi exe deb rpm appimage apk
Code & Scripts|py ipynb sh zsh bash js mjs cjs ts tsx jsx json jsonl yaml yml toml xml sql css scss sass less c cc cpp h hpp java rb go rs php swift kt kts scpt applescript plist ini cfg conf env lua pl
Design|psd ai sketch fig xd eps indd afdesign afphoto afpub
Fonts|ttf otf ttc woff woff2 fon pfb pfm
3D & CAD|stl obj fbx blend 3ds dae dwg dxf step stp igs iges gltf glb ply usdz 3mf
Torrents|torrent
Data|sqlite sqlite3 db accdb mdb dat parquet avro
Calendars & Contacts|ics ical vcf vcard
Invoices & Receipts|names containing: invoice, receipt, statement, billing, bill_, bill-
Misc|anything not matched above
EOF
}

main() {
    : > "$UNDO_PARTIAL" 2>/dev/null              # fresh undo record for this run
    scan
    # a fresh download usually finishes within MIN_AGE: instead of leaving young
    # files for the next timer pass, wait them out once and rescan
    if [ "$YOUNG_SKIPPED" = 1 ]; then
        sleep $((WAIT + 2))
        scan
    fi
    archive_old
    prune_empty
    # append this run's moves to the undo history (stack), stamped with the run
    if [ "$MOVE_COUNT" -gt 0 ] || [ "$ARCHIVE_COUNT" -gt 0 ]; then
        local _stamp _h
        _stamp=$(date +%s)
        while IFS= read -r _h || [ -n "$_h" ]; do
            [ -n "$_h" ] && printf '%s\t%s\n' "$_stamp" "$_h" >> "$HISTORY_FILE"
        done < "$UNDO_PARTIAL"
        # keep the history bounded (~last 2000 moves)
        if [ "$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)" -gt 3000 ]; then
            tail -n 2000 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" 2>/dev/null && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
        fi
    fi
    rm -f "$UNDO_PARTIAL" 2>/dev/null
    notify
    aging_notice
}

# Run only when executed directly; allow `source` (migration helper) with no side effects.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
    exit 0
fi
