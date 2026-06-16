<div align="center">

# 🗂️ Downloads Sorter

**Keep your macOS Downloads folder tidy — automatically.**
It watches `~/Downloads` and files every new download into clean category folders the instant it lands.

![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white)
![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![Built with bash](https://img.shields.io/badge/built%20with-bash-4EAA25?logo=gnubash&logoColor=white)
![sudo](https://img.shields.io/badge/sudo-never-success)

</div>

---

## Why you'll like it

| | |
|---|---|
| 🗂️ **Sorts automatically** | A nested library — Media, Documents, Compressed Files, Disk Images, Code, Design, and more. |
| ⚡ **Instant** | Reacts the moment a download lands (folder‑watching), with a timed safety‑net pass as backup. |
| ↩️ **Never deletes your files** | Every move is logged and fully undoable — even past sortings. |
| 🪶 **Featherweight** | ~0.05 s per run, low priority, runs entirely in your user account — **no sudo, nothing system‑wide.** |
| 🎛️ **Yours to shape** | A friendly terminal menu *and* a full scriptable CLI. Custom rules, folder colours, filters, and more. |

---

## Contents

- [Install](#install) · [Permissions](#permissions)
- [How your Downloads get organised](#how-your-downloads-get-organised)
- [The menu](#the-menu) · [Command reference](#command-reference)
- [Features](#features) — [custom rules](#custom-rules) · [folder colours](#folder-colours) · [empty‑folder cleanup](#empty-folder-cleanup) · [limit what gets sorted](#limit-what-gets-sorted)
- [Safety & privacy](#safety--privacy) · [How it works](#how-it-works)
- [Updating](#updating) · [Uninstall](#uninstall) · [Requirements](#requirements) · [License](#license)

---

## Install

```sh
git clone https://github.com/Lucid06-K/mac-downloads-sorter.git
cd mac-downloads-sorter
bash install.sh
```

That's it — the installer copies two small scripts into `~/Library/Scripts`, builds two tiny helper apps, starts the sorter in the background, and adds the **`dsort`** command.

> ⚠️ **Restart your shell (or open a new terminal tab) before using `dsort`** — the command won't be available until the shell reloads.

### Already cloned it before?

If you cloned the repo on a previous attempt, `git clone` will fail with *"destination path already exists."* You don't need to re‑clone — just pull the latest code and re‑run the installer **from inside the existing folder**:

```sh
cd mac-downloads-sorter   # the folder you cloned into earlier
git pull                  # fetch the newest version
bash install.sh           # re-run the installer
```

> **Notes**
> - Run it with **`bash install.sh`** (not `./install.sh`) — that works even if the file isn't marked executable, so you'll never hit a `permission denied`.
> - Re‑running is **safe**: it updates the scripts, rebuilds anything missing, and keeps your settings and existing permission grants.
> - If `git pull` ever reports a conflict (e.g. you edited a file locally), the simplest reset is to delete the folder and clone fresh: `cd .. && rm -rf mac-downloads-sorter && git clone https://github.com/Lucid06-K/mac-downloads-sorter.git`
>
> Already installed and just want the latest version? You don't need git at all — run **`dsort update`** ([details below](#updating)).

### Permissions

macOS protects your folders and notifications, so during install you'll see **two prompts — click _Allow_ on both:**

| Prompt | Why it's needed |
|---|---|
| **Files & Folders → Downloads Folder** | so the sorter can move your downloads into folders |
| **Notifications** | so it can tell you what it just sorted and where it was sorted *(optional — you can turn it off later)* |

These are granted to the small helper apps the installer builds **on your Mac** (`OrganizeDownloads.app`, `DownloadsNotifier.app`). They can't ship pre‑approved — macOS ties permissions to each app's identity on each machine — which is exactly why the installer builds them locally.

> Missed the Downloads prompt? Drop any file in `~/Downloads` and run `dsort run` — macOS will ask then. You can always check under **System Settings → Privacy & Security → Files and Folders**.

---

## How your Downloads get organised

```
~/Downloads/
├── Screenshots/        2026-06/2026-06-14 Screenshot.png   (dated, by month)
├── Media/              Images · Audio · Video
├── Documents/          PDFs · Slides · Spreadsheets · Word & Text · eBooks · Web
├── Compressed Files/   zip, tar, 7z, rar …
├── Disk Images/        dmg, iso …
├── Installers & Apps/  pkg, app, exe …
├── Code & Scripts/     py, js, sh, json …
├── Design/   Fonts/   3D & CAD/   Torrents/   Data/   Calendars & Contacts/
├── Invoices & Receipts/   anything named invoice / receipt / statement
├── Misc/               everything else
├── Duplicates/         byte‑identical copies, set aside for review
├── Large Files/        files at/above your size threshold
└── Archive/            mirrors all of the above for files older than 15 days
```

> Only **loose files at the top of `~/Downloads`** are sorted. **Any folder you create yourself is left untouched.**

---

## The menu

```sh
dsort
```

```
 Downloads Sorter
 ──────────────────────
  Sorter            ● ON
 ──────────────────────
  Sort now
  Preview (dry run)
  Undo
  Stats
  Activity log
 ──────────────────────
  Settings ▸
  Check for updates
  Help & guide
  Close menu
```

Navigate with **↑/↓ + Enter**, or press a **number** to jump straight to a row. **Settings ▸** opens a second screen with every toggle, tunable, and sub‑editor (custom rules, folder colours, filters, empty‑folder cleanup…). **Esc** goes back, **q** quits. Every row shows a one‑line explanation, and there's a full in‑app **Help & guide**.

---

## Command reference

Everything the menu does is scriptable. `dsort` is an alias to `~/Library/Scripts/downloads-sorter`.

**Everyday**

| Command | What it does |
|---|---|
| `dsort` | open the menu |
| `dsort run` | sort now |
| `dsort preview` | dry run — show where things *would* go (moves nothing) |
| `dsort undo` | revert the last run (repeat to keep stepping back) |
| `dsort find <name>` | "where did it go?" — locate a download in your sorted folders |
| `dsort stats` | counts + sizes per category |
| `dsort log [n]` | recent activity |
| `dsort status` | show every current setting |

**On/off toggles** — `dsort <name> on|off`

| Toggle | Default | Effect |
|---|---|---|
| `notify` | on | banner summarising each sort |
| `detect` | off | heads‑up the moment a download is spotted (where it'll go + the wait) |
| `digest` | off | weekly "what got sorted" summary |
| `cleannames` | off | tidy messy download names |
| `aging` | on | weekly nudge for `Archive/` files over a year old |
| `duplicates` | on | route byte‑identical files to `Duplicates/` |
| `screenshotdate` | on | date‑prefix screenshots + bucket by month |
| `metanames` | off | rename PDFs from their embedded title |
| `autounzip` | off | expand `.zip` into a same‑named subfolder |
| `on` / `off` | — | enable/disable the **whole** sorter |

**Tunables** — `d` = default

| Command | Meaning |
|---|---|
| `dsort interval [seconds\|d]` | safety‑net auto‑run cadence |
| `dsort graceperiod [seconds\|d]` | settle time before sorting (`0` = immediate, max 31 days) |
| `dsort archivedays [days\|d]` | move to `Archive/` after this many days |
| `dsort largefiles [GB\|d]` | `Large Files/` threshold (`0` = off) |
| `dsort recentcount [0‑10\|d]` | recent moves listed under the main menu (`0` = hide) |

**Manage** — see each feature below

| Command | Meaning |
|---|---|
| `dsort rules` | list your custom sorting rules |
| `dsort colours [..]` | Finder colour tags for category folders |
| `dsort cleanfolders [..]` | empty‑folder cleanup scope + lists |
| `dsort exclude / only [..]` | limit what gets sorted |
| `dsort update` / `dsort version` | update / show installed version |

---

## Features

<details open>
<summary><b>Always on</b></summary>

- **Sorting** — by your custom rules first, then filename keywords (screenshots, `SCR‑…`, invoices…), then file extension.
- **Archive** — files older than the *archive age* (default 15 days, by modified date) move into `Archive/`, keeping the same layout.
- **Duplicate routing** — a byte‑identical file (same size + checksum) goes to `Duplicates/` instead of becoming `name (2)`.
- **Big‑file quarantine** — files at/above the threshold (default **5 GB**) go to `Large Files/` so you handle them deliberately. `Duplicates/` and `Large Files/` are never auto‑archived.
- **Screenshot dating** — `Screen Shot …` / `SCR‑…` become `2026-06-14 Screenshot.png`, filed into `Screenshots/YYYY-MM/`.
- **Aging nudge** — a weekly heads‑up if `Archive/` holds anything over a year old. It **never deletes**.
- **Notifications** — a banner after each sort, grouped by category (e.g. `3 -> Documents/PDFs, 2 -> Media/Images`).

</details>

<details>
<summary><b>Opt‑in</b> (off until you turn them on)</summary>

- **Detected heads‑up** — a banner the moment a download is spotted, showing where it'll go and the grace‑period wait (e.g. `report.pdf -> Documents/PDFs (sorting in ~2m)`). *Settings → Notifications.*
- **Filename cleanup** — strips URL junk (`%20`, `?token=…`), long random hash blobs, and trailing `copy`/`v2`. Conservative (it protects real names like `Chapter_03_Glycolysis`); every rename is logged and undoable.
- **Metadata naming** — renames PDFs from their embedded title (via Spotlight's `mdls`).
- **Auto‑unzip** — expands `.zip` files into a same‑named subfolder (size‑guarded against zip‑bombs; contents aren't re‑sorted).
- **Weekly digest** — a once‑a‑week notification summarising the week (file count, archived count, top categories). Silent in weeks with no activity.

</details>

<details>
<summary><b>Tunables</b> — how the pickers work</summary>

Every tunable is set **right inside the menu** — `↑`/`↓` to move, type to enter a number, `enter` to save, `esc` to cancel. Nothing drops to a raw command‑line prompt.

- **Auto‑run interval** (default **12h**) and **big‑file size** (default **5 GB**) are arrow‑key pickers of sensible presets.
- **Grace period** (default **5m**) is a **Days / Hours / Minutes / Seconds** form — type a number in each field and they add up (e.g. Minutes `1` + Seconds `30` = `1m 30s`), up to 31 days. `0` = sort immediately (and turns off the detected heads‑up, since there's no waiting window).
- **Archive age** (default **15 days**) and **recent‑count** (default **3**) are single‑field number forms with the same look and keys.

Each tunable marks its **default** so you can always get back to a sensible setting.

</details>

### Custom rules

Send matching files to a folder of your choice — these override the built‑in categories. Add them in **Settings → Custom sorting rules**: first choose **what to match — the filename, or the website the file came from** — then pick the destination (no file editing). Stored in `~/.downloads-rules.conf` if you'd rather edit by hand:

```text
# pattern                  destination
*statement*             -> Documents/Finance
*.dwg                   -> 3D & CAD
*figma*                 -> Design
source:*github.com*     -> Installers & Apps
source:*unimelb.edu.au* -> Course
```

A plain pattern matches the **filename**. Prefix it with **`source:`** to match the **download origin** instead — macOS tags each download with where it came from (`kMDItemWhereFroms`), so `source:*github.com*` files everything from GitHub, `source:*unimelb.edu.au*` everything from your university. The arrow may be `->` or `→`; `#` lines are comments. Rules are checked **before** the built‑ins, in file order. List with `dsort rules`.

> Files created locally (no download origin) simply fall through to the normal filename/extension rules.

### Folder colours

Give any category folder a **Finder colour tag** so `~/Downloads` is colour‑coded at a glance — **Settings → Folder colours** (pick a category, pick a colour). The sorter re‑applies your colours automatically, so new category folders get tagged too. Uses standard Finder tag metadata — **no extra permissions.**

```sh
dsort colours                          # list your colour assignments
dsort colours "Invoices & Receipts" Red
dsort colours "Media" Blue
dsort colours "Media" None             # clear one
dsort colours clear                    # clear all
```

> Colours: Red, Orange, Yellow, Green, Blue, Purple, Gray.

### Empty‑folder cleanup

The sorter's own empty category folders are **always** tidied — including ones that only *look* empty because of a hidden `.DS_Store` or an orphaned `~$…` Office lock. **Settings → Empty‑folder cleanup** lets you widen this with a **scope**:

| Scope | Removes empty… |
|---|---|
| **Category folders only** *(default)* | just this app's folders |
| **Also folders you created** | category folders **+** your own folders |
| **Every folder** | any empty folder in `~/Downloads` |

Hidden folders (`.*`, which covers Syncthing's `.stfolder`) are **always protected**. For the wider scopes, add a **blacklist** (never delete) and/or a **whitelist** (if set, only delete matching folders).

```sh
dsort cleanfolders                       # show scope + list counts
dsort cleanfolders user                  # set scope: managed | user | all
dsort cleanfolders keep Temp node_modules   # blacklist (never delete)
dsort cleanfolders only Builds           # whitelist (if set, only these)
dsort cleanfolders keepclear             # clear blacklist (onlyclear for whitelist)
```

> A folder is removed only when it's genuinely empty (or holds nothing but disposable junk) — **a real file is never deleted** (a `~$` lock next to its actual document is kept).

### Limit what gets sorted

Two multi‑select checklists in **Settings** control scope — tick categories and/or type file extensions:

- **Exclude from sorting** — matching files are left where they are, and their folder is never created.
- **Only sort these** — if you pick anything, **only** matching files are sorted; everything else is left alone.

Combine them freely (e.g. *only* `Media`, but *exclude* `heic`).

```sh
dsort exclude Torrents dmg     # never sort torrents or .dmg files
dsort only Documents Media     # sort only these; leave the rest alone
dsort exclude                  # list current exclusions
dsort exclude clear            # clear the exclude list
```

> Entries are a **category** (`Media`, `Documents/PDFs`, …) or a bare **extension** (`dmg`, `heic`).

---

## Safety & privacy

- **Never deletes your files.** Moves are no‑clobber (a name clash becomes `name (2)`). The *only* things removed are **empty folders** and the disposable junk inside them (`.DS_Store`, orphaned `~$…` locks) — by default just the sorter's own category folders; widen it under [Empty‑folder cleanup](#empty-folder-cleanup). A real file is never touched.
- **Undo, including past sortings.** A history stack lets you revert individual changes or whole runs and keep stepping back (`dsort undo`, repeatable; or pick items in the menu). The first time you open Undo it even rebuilds revertable entries from the activity log for files still in their sorted folders — so older moves can be undone too. Undo only ever **moves files back**.
- **Leaves cloud "online‑only" files alone.** iCloud "Optimize Mac Storage" and Dropbox/OneDrive/Google Drive placeholders are skipped, so sorting never forces a multi‑GB download. They sort normally once downloaded.
- **The 30‑day archive only moves files** into `Archive/` — never removes them; the aging nudge only *reminds*.
- **Everything is logged** to `~/Library/Logs/organize-downloads.log`.
- **No sudo, nothing system‑wide** — it lives entirely in your user account.

> Found a security issue? Please report it privately — see the [security policy](SECURITY.md).

---

## How it works

- A per‑user **launchd agent** runs the sorter when `~/Downloads` changes (`WatchPaths`) and periodically as a backup (`StartInterval`), at low `Background` priority.
- The agent runs a tiny **AppleScript app** (`OrganizeDownloads.app`) rather than bare `bash`, because macOS grants *Downloads* access to an app identity, not a raw shell. A separate `DownloadsNotifier.app` posts notifications (a bare `osascript` notification under launchd is silently dropped — it has no app identity to register).
- The logic is two plain‑bash scripts in `~/Library/Scripts`: `organize_downloads.sh` (the sorter) and `downloads-sorter` (the menu/CLI).

---

## Updating

```sh
dsort update     # check GitHub and install the latest version
dsort version    # what you have installed now
```

Or use **Check for updates** in the menu. Turn on **Settings → Auto‑update** to check once a day on open and install verified updates automatically — **off by default**.

**Updates are kept safe:**

- **HTTPS only**, pinned to this repository (redirects forced to HTTPS too).
- Verified against the repo's published **SHA‑256 checksums** — a mismatch (corruption or tampering) aborts the update.
- **Syntax‑checked** before anything is replaced; current scripts backed up to `*.bak`.
- **User space only — never `sudo`.**

> Checksum + HTTPS protect the download path; for a manual update you can review the diff on GitHub first. As with any auto‑updater you're ultimately trusting the source repo, which is why auto‑update is opt‑in.

---

## Uninstall

```sh
bash uninstall.sh
```

Removes the scripts, helper apps, launch agent, and settings. **Your sorted files and folders in `~/Downloads` are left exactly as they are.**

---

## Requirements

macOS only. Uses `launchd`, `osacompile`, `ditto`, `mdls` — all built in. **No Homebrew or other dependencies.**

## License

[Apache License 2.0](LICENSE) — © 2026 Lucid06‑K (see [NOTICE](NOTICE)).
