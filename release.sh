#!/bin/bash
# Copyright 2026 Lucid06-K
# SPDX-License-Identifier: Apache-2.0
#
# Downloads Sorter — release helper.
#
# One command to cut a release so the easy-to-forget steps can't be skipped:
# bump BOTH version sources, regenerate the checksum manifest, and — critically —
# SIGN it. From 1.0.33 on, an unsigned/mis-signed manifest makes `dsort update`
# fail closed for EVERY user, so signing is mandatory: this script verifies the
# signature it just made and refuses to ship if anything is off.
#
# Usage:
#   ./release.sh 1.0.34 -m "fix: thing"   # full: bump → sign → commit → push
#   ./release.sh 1.0.34                    # prepare + sign + stage; you commit/push
#   ./release.sh --dry-run 1.0.34          # validate only; change nothing
#
# Signing key: $DSORT_SIGNING_KEY, else ~/.config/dsort/update.key (see SIGNING.md).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
SRC="$HERE/src"
CTL_SRC="$SRC/downloads-sorter"          # the menu/CLI (carries VERSION + UPDATE_PUBKEY)
SORTER_SRC="$SRC/organize_downloads.sh"  # the sorter
SCRIPTS="$HOME/Library/Scripts"
KEY="${DSORT_SIGNING_KEY:-$HOME/.config/dsort/update.key}"

BLD=$'\033[1m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; R=$'\033[0m'
bold(){ printf '%s%s%s\n' "$BLD" "$1" "$R"; }
ok(){   printf '  %s✓%s %s\n' "$GRN" "$R" "$1"; }
info(){ printf '  %s• %s%s\n' "$DIM" "$1" "$R"; }
warn(){ printf '  %s! %s%s\n' "$YEL" "$1" "$R"; }
die(){  printf '  %s✗ %s%s\n' "$RED" "$1" "$R" >&2; exit 1; }
usage(){ sed -n '5,18p' "$0" | sed 's/^# \{0,1\}//'; }

ver_gt(){ [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }

# --- args ------------------------------------------------------------------
DRY=0; MSG=""; NEW=""
while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY=1 ;;
        -m|--message) shift; MSG="${1:-}" ;;
        -h|--help)    usage; exit 0 ;;
        -*)           die "unknown option: $1 (try --help)" ;;
        *)            [ -z "$NEW" ] && NEW="$1" || die "unexpected argument: $1" ;;
    esac
    shift
done

# --- preconditions ---------------------------------------------------------
[ -f "$CTL_SRC" ] && [ -f "$SORTER_SRC" ] || die "run me from the repo root (src/ not found)"
command -v openssl >/dev/null 2>&1 || die "openssl not found"
command -v shasum  >/dev/null 2>&1 || die "shasum not found"
[ -n "$NEW" ] || { usage; exit 1; }
printf '%s' "$NEW" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "version must be x.y.z (got: $NEW)"

CUR=$(grep -m1 '^VERSION=' "$CTL_SRC" | cut -d'"' -f2)
[ -n "$CUR" ] || die "couldn't read current VERSION from src/downloads-sorter"
ver_gt "$NEW" "$CUR" || die "new version $NEW is not greater than current $CUR"
[ -r "$KEY" ] || die "signing key not found at $KEY — set DSORT_SIGNING_KEY or see SIGNING.md"

bold "Releasing Downloads Sorter  v$CUR → v$NEW"
info "signing key: $KEY"
[ "$DRY" = 1 ] && info "DRY RUN — nothing will be changed, signed, or pushed"

# --- 1. bump both version sources -----------------------------------------
if [ "$DRY" = 0 ]; then
    sed -i '' 's/^VERSION="[^"]*"/VERSION="'"$NEW"'"/' "$CTL_SRC"
    printf '%s\n' "$NEW" > "$HERE/VERSION"
    ok "VERSION bumped in src/downloads-sorter and repo-root VERSION"
else
    info "would bump VERSION → $NEW (src/downloads-sorter + repo-root VERSION)"
fi

# --- 2. syntax check -------------------------------------------------------
bash -n "$CTL_SRC"    || die "syntax error in src/downloads-sorter"
bash -n "$SORTER_SRC" || die "syntax error in src/organize_downloads.sh"
ok "bash -n syntax check passed"

# --- 3. regenerate + sign the manifest (the step you must never forget) ----
# Even in --dry-run we actually sign (to throwaway temp files) so the run truly
# proves the key works, the signature verifies, and it matches the client's key.
if [ "$DRY" = 1 ]; then man="$(mktemp)"; sig="$man.sig"; else man="$HERE/SHA256SUMS"; sig="$HERE/SHA256SUMS.sig"; fi
# explicit names (not *) so the manifest lists exactly what the updater fetches
( cd "$SRC" && shasum -a 256 organize_downloads.sh downloads-sorter > "$man" )
openssl dgst -sha256 -sign "$KEY" -out "$sig" "$man"

# self-check: the signature we just made must verify with the key's own pubkey
pub=$(openssl pkey -in "$KEY" -pubout 2>/dev/null) || die "couldn't derive public key from $KEY"
printf '%s\n' "$pub" > "$HERE/.relpub.tmp"
if ! openssl dgst -sha256 -verify "$HERE/.relpub.tmp" -signature "$sig" "$man" >/dev/null 2>&1; then
    rm -f "$HERE/.relpub.tmp"; [ "$DRY" = 1 ] && rm -f "$man" "$sig"; die "signature self-check FAILED — not shipping"
fi
rm -f "$HERE/.relpub.tmp"

# cross-check: signing key vs the public key baked into the client. They match
# for a normal release; a mismatch means clients will REJECT this build unless
# it's an intentional key rotation (sign with OLD key — see SIGNING.md).
emb=$(awk '/^UPDATE_PUBKEY="/{f=1;sub(/^UPDATE_PUBKEY="/,"");print;next} f{print; if(/-----END PUBLIC KEY-----"$/)exit}' "$CTL_SRC" | sed 's/"$//')
if [ "$emb" != "$pub" ]; then
    warn "signing key ≠ UPDATE_PUBKEY in the client — clients will REJECT this release"
    warn "(expected only during a key rotation handoff; see SIGNING.md)"
fi

if [ "$DRY" = 1 ]; then
    rm -f "$man" "$sig"
    ok "signing validated (key OK · signature verifies · matches client key)"
else
    ok "SHA256SUMS regenerated and signed (SHA256SUMS.sig) — signature verified"
fi

# --- 4. sync the live copy on THIS machine (label-preserving, optional) ----
if [ -f "$SCRIPTS/downloads-sorter" ]; then
    if [ "$DRY" = 0 ]; then
        live_label=$(grep -m1 '^LABEL=' "$SCRIPTS/downloads-sorter" 2>/dev/null || true)
        cp "$SORTER_SRC" "$SCRIPTS/organize_downloads.sh"
        cp "$CTL_SRC"    "$SCRIPTS/downloads-sorter"
        [ -n "$live_label" ] && sed -i '' "s|^LABEL=.*|$live_label|" "$SCRIPTS/downloads-sorter"
        chmod 0755 "$SCRIPTS/organize_downloads.sh" "$SCRIPTS/downloads-sorter"
        ok "live copy in ~/Library/Scripts synced (LABEL preserved)"
    else
        info "would sync live copy in ~/Library/Scripts (LABEL preserved)"
    fi
else
    info "no live install on this machine — skipping live sync"
fi

# --- 5. dry run stops here -------------------------------------------------
if [ "$DRY" = 1 ]; then
    bold "Dry run OK — v$NEW would be valid. Re-run without --dry-run to cut it."
    exit 0
fi

# --- 6. stage, guard against key material, commit + push -------------------
git add -A
if git diff --cached --name-only | grep -iqE '\.(key|pem)$|update\.key'; then
    die "refusing to commit — key material is staged (check .gitignore)"
fi
[ -s "$HERE/SHA256SUMS.sig" ] || die "SHA256SUMS.sig missing — refusing to commit an unsigned release"
ok "staged release files (no key material)"

if [ -n "$MSG" ]; then
    git commit -m "$MSG"
    git push
    bold "Released v$NEW ✓  (committed + pushed)"
    info "CDN can lag ~5 min before 'dsort update' sees it."
else
    bold "Prepared & signed v$NEW — staged but not committed."
    printf '    review:  git diff --cached --stat\n'
    printf '    ship:    git commit -m "…" && git push\n'
fi
