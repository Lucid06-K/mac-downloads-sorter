# Downloads Sorter

A lightweight macOS tool that keeps your **Downloads folder tidy automatically**. It watches `~/Downloads` and files every new download into clean category folders — the instant it lands — and never deletes anything.

- 🗂️ Sorts into a nested library (Media, Documents, Compressed Files, Disk Images, Code, Design, Fonts, and more)
- ⚡ Reacts instantly to new downloads (folder‑watching) + an hourly safety‑net pass
- 🧹 Optional extras: filename cleanup, duplicate detection, big‑file quarantine, screenshot dating, auto‑unzip
- 🗄️ Auto‑archives files older than 30 days into a mirrored `Archive/`
- ↩️ **Never deletes or overwrites** — every move is logged and can be undone
- 🎛️ Friendly terminal menu **and** scriptable commands
- 🪶 Featherweight: ~0.05 s per run, low‑priority, ~24 wake‑ups a day

> Works entirely within your user account — **no sudo, nothing system‑wide.**

---

## Install

```sh
git clone https://github.com/Lucid06-K/mac-downloads-sorter.git
cd mac-downloads-sorter
bash install.sh
```

> Already cloned it once? `cd` into the folder and run `git pull` first (or delete the folder and re‑clone). Running `bash install.sh` works even if the script isn't marked executable.

That's it. The installer copies two small scripts into `~/Library/Scripts`, builds two tiny helper apps, and starts the sorter in the background.

### Permissions you'll be asked for (and why)

macOS protects your folders and notifications, so during install you'll see **two prompts — click _Allow_ on both**:

| Prompt | Why it's needed |
| --- | --- |
| **Files & Folders → Downloads Folder** | so the sorter can move your downloads into folders |
| **Notifications** | so it can tell you what it just sorted (optional — you can turn it off later) |

These are granted to the small helper apps the installer builds on your Mac (`OrganizeDownloads.app` and `DownloadsNotifier.app`). They can't be shipped pre‑approved — macOS ties permissions to each app's identity on each machine — which is exactly why the installer builds them locally.

> If you miss the Downloads prompt, just drop any file in `~/Downloads` and run `dsort run`; macOS will ask then. You can always check under **System Settings → Privacy & Security → Files and Folders**.

---

## What the folders look like

```
~/Downloads/
├── Screenshots/2026-06/2026-06-14 Screenshot.png
├── Media/        Images · Audio · Video
├── Documents/    PDFs · Slides · Spreadsheets · Word & Text · eBooks · Web
├── Compressed Files/        zip, tar, 7z, rar …
├── Disk Images/             dmg, iso …
├── Installers & Apps/       pkg, app, exe …
├── Code & Scripts/          py, js, sh, json …
├── Design/  Fonts/  3D & CAD/  Torrents/  Data/  Calendars & Contacts/
├── Invoices & Receipts/     anything named invoice / receipt / statement
├── Misc/                    everything else
├── Duplicates/              byte‑identical copies, set aside for review
├── Large Files/             files at/above your size threshold
└── Archive/                 mirrors all of the above for files older than 30 days
```

Only **loose files at the top of `~/Downloads`** are sorted. **Any folder you create yourself is left completely untouched.**

---

## Using it

Open the menu:

```sh
dsort
```

It has two screens — a compact **main menu** and a **Settings** submenu:

```
 Downloads Sorter                     Downloads Sorter · Settings
 ─────────────────                    ─────────────────
  Sorter          ● ON                 Notifications      ● ON
 ─────────────────                     Filename cleanup   ○ OFF
  Sort now                             Auto-run interval  every 1h
  Preview (dry run)                    Archive age        30 days
  Undo                                 Aging nudge        ● ON
  Stats                                Duplicate routing  ● ON
  Activity log                         Big files          ≥ 5 GB
 ─────────────────                     Screenshot dating  ● ON
  Settings ▸                           Metadata naming    ○ OFF
  Help & guide                         Auto-unzip         ○ OFF
  Close menu                           ← Back to menu
```

Navigate with **↑/↓ + Enter**, or press a **number (1‑9)** to jump straight to an item. In Settings, **Esc** goes back; **q** quits anywhere. Every row shows a one‑line explanation, and there's a full in‑app **Help & guide**.

### Command line

Everything the menu does is scriptable:

```sh
dsort                 # open the menu
dsort status          # show every current setting
dsort run             # sort now
dsort preview         # dry run — show where things would go (moves nothing)
dsort undo            # revert the last run (repeat to keep stepping back)
dsort find <name>     # "where did it go?" — locate a download in your sorted folders
dsort stats           # counts + sizes per category
dsort rules           # list your custom rules
dsort log [n]         # recent activity

# toggles
dsort notify on|off
dsort cleannames on|off
dsort aging on|off
dsort duplicates on|off
dsort screenshotdate on|off
dsort metanames on|off
dsort autounzip on|off

# tunables (r = recommended)
dsort interval [seconds|r]
dsort archivedays [days|r]
dsort largefiles [GB|r]     # 0 = off

dsort on|off          # enable/disable the whole sorter
```

> `dsort` is the command the installer sets up (an alias to the `downloads-sorter` script in `~/Library/Scripts`).

---

## Features in detail

**Always on**
- **Sorting** — by your custom rules first, then filename keywords (screenshots, `SCR-…`, invoices…), then file extension.
- **Archive** — files older than the *archive age* (default 30 days, by modified date) move into `Archive/`, keeping the same folder layout.
- **Duplicate routing** — a byte‑identical file (same size + checksum) goes to `Duplicates/` instead of becoming `name (2)`.
- **Big‑file quarantine** — files at/above the threshold (default **5 GB**) go to `Large Files/` so you deal with them deliberately. `Duplicates/` and `Large Files/` are never auto‑archived.
- **Screenshot dating** — `Screen Shot …` / `SCR-…` become `2026-06-14 Screenshot.png`, filed into `Screenshots/YYYY-MM/`.
- **Aging nudge** — a weekly heads‑up if `Archive/` holds anything over a year old. It **never deletes**.
- **Notifications** — a banner after each sort, grouped by category (e.g. “3 → Documents/PDFs, 2 → Media/Images”).

**Opt‑in (OFF until you turn them on)**
- **Filename cleanup** — tidies messy names: strips URL junk (`%20`, `?token=…`), long random hash blobs, and trailing `copy`/`v2`. Conservative by design (it protects real names like `Chapter_03_Glycolysis`), and every rename is logged and undoable.
- **Metadata naming** — renames PDFs from their embedded title (via Spotlight’s `mdls`).
- **Auto‑unzip** — expands `.zip` files into a same‑named subfolder (size‑guarded against zip‑bombs; contents are not re‑sorted).

**Tunables** — the auto‑run interval and big‑file size are arrow‑key pickers; the archive age is a number entry. Each shows a recommended value so you can always get back to a sensible default.

### Custom rules

Add and manage these right in the menu — **Settings → Custom sorting rules** (type a pattern, pick the destination folder; no file editing). They're stored in `~/.downloads-rules.conf` if you'd rather edit by hand:

```
# pattern              destination
*statement*         -> Documents/Finance
*.dwg               -> 3D & CAD
*figma*             -> Design
```

The arrow may be `->` or `→`; `#` lines are comments. Rules are checked **before** the built‑in categories. List them with `dsort rules`.

### Limit what gets sorted

Two multi‑select checklists in **Settings** let you control scope — tick categories and/or type in file extensions:

- **Exclude from sorting** — matching files are left exactly where they are, and their folder is never created (e.g. exclude `Torrents` + `dmg`).
- **Only sort these** — if you pick anything here, **only** matching files are sorted; everything else is left alone (e.g. only `Documents` + `Media`).

You can combine them (only `Media`, but exclude `heic`). From the command line:

```sh
dsort exclude Torrents dmg     # never sort torrents or .dmg files
dsort only Documents Media     # sort only these; leave the rest alone
dsort exclude                  # list current exclusions
dsort exclude clear            # clear the exclude list
```

Entries are either a **category** (`Media`, `Documents/PDFs`, …) or a bare **file extension** (`dmg`, `heic`).

---

## Safety

- **Never deletes or overwrites.** Moves use a no‑clobber strategy and add ` (2)` on a name clash.
- **Everything is logged** to `~/Library/Logs/organize-downloads.log`.
- **Undo** keeps a history stack: revert individual changes, or whole runs, and keep stepping back run‑by‑run (`dsort undo`, repeatable; or pick items in the menu's Undo screen).
- **Undo reaches back to past sortings too.** The first time you open Undo it rebuilds revertable entries from the activity log for any sorted file still sitting in its folder — so moves made before you had the latest version can still be undone. (Reconstruction is conservative: it only offers a file that's actually still at its sorted location, and — as always — only ever moves files back, never deletes.)
- The 30‑day archive only **moves** files (into `Archive/`) — it never removes them, and the aging nudge only *reminds* you.

---

## How it works (under the hood)

- A per‑user **launchd agent** runs the sorter when `~/Downloads` changes (`WatchPaths`) and hourly as a backup (`StartInterval`), at low `Background` priority.
- The agent runs a small **AppleScript app** (`OrganizeDownloads.app`) instead of bare `bash`, because macOS grants *Downloads* access to an app identity, not to a raw shell. A separate `DownloadsNotifier.app` posts notifications (a bare `osascript` notification under launchd is silently dropped — it has no app identity to register).
- The actual logic is two plain‑bash scripts in `~/Library/Scripts`: `organize_downloads.sh` (the sorter) and `downloads-sorter` (the menu/CLI).

---

## Updating

```sh
dsort update     # check GitHub and install the latest version
dsort version    # what you have installed now
```

Or use **Check for updates** in the menu. Turn on **Settings → Auto‑update** to have it check once a day (when you open the menu) and install verified updates automatically — it's **off by default**.

**How updates are kept safe:**
- Downloads come **over HTTPS only**, pinned to this repository (redirects are also forced to HTTPS).
- They're verified against the repo's published **SHA‑256 checksums** — a mismatch (corruption or tampering) aborts the update.
- They're **syntax‑checked** before anything is replaced, and the current scripts are backed up to `*.bak`.
- Everything runs in **user space — never `sudo`**.

Checksum + HTTPS verification protects the download path; for a manual update you can review the diff on GitHub first. As with any auto‑updater you are ultimately trusting the source repo, which is why auto‑update is opt‑in.

## Uninstall

```sh
bash uninstall.sh
```

Removes the scripts, helper apps, launch agent, and settings. **Your sorted files and folders in `~/Downloads` are left exactly as they are.**

---

## Requirements

macOS (uses `launchd`, `osacompile`, `ditto`, `mdls` — all built in). No Homebrew or other dependencies required.

## License

[Apache License 2.0](LICENSE) — © 2026 Lucid06‑K.
