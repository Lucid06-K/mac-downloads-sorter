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
git clone https://github.com/Lucid06-K/downloads-sorter.git
cd downloads-sorter
./install.sh
```

That's it. The installer copies two small scripts into `~/Library/Scripts`, builds two tiny helper apps, and starts the sorter in the background.

### Permissions you'll be asked for (and why)

macOS protects your folders and notifications, so during install you'll see **two prompts — click _Allow_ on both**:

| Prompt | Why it's needed |
| --- | --- |
| **Files & Folders → Downloads Folder** | so the sorter can move your downloads into folders |
| **Notifications** | so it can tell you what it just sorted (optional — you can turn it off later) |

These are granted to the small helper apps the installer builds on your Mac (`OrganizeDownloads.app` and `DownloadsNotifier.app`). They can't be shipped pre‑approved — macOS ties permissions to each app's identity on each machine — which is exactly why the installer builds them locally.

> If you miss the Downloads prompt, just drop any file in `~/Downloads` and run `downloads-sorter run`; macOS will ask then. You can always check under **System Settings → Privacy & Security → Files and Folders**.

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
downloads-sorter
```

It has two screens — a compact **main menu** and a **Settings** submenu:

```
 Downloads Sorter                     Downloads Sorter · Settings
 ─────────────────                    ─────────────────
  Sorter          ● ON                 Notifications      ● ON
 ─────────────────                     Filename cleanup   ○ OFF
  Sort now                             Auto-run interval  every 1h
  Preview (dry run)                    Archive age        30 days
  Undo last run                        Aging nudge        ● ON
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
downloads-sorter                 # open the menu
downloads-sorter status          # show every current setting
downloads-sorter run             # sort now
downloads-sorter preview         # dry run — show where things would go (moves nothing)
downloads-sorter undo            # move the last run's files back
downloads-sorter stats           # counts + sizes per category
downloads-sorter rules           # list your custom rules
downloads-sorter log [n]         # recent activity

# toggles
downloads-sorter notify on|off
downloads-sorter cleannames on|off
downloads-sorter aging on|off
downloads-sorter duplicates on|off
downloads-sorter screenshotdate on|off
downloads-sorter metanames on|off
downloads-sorter autounzip on|off

# tunables (r = recommended)
downloads-sorter interval [seconds|r]
downloads-sorter archivedays [days|r]
downloads-sorter largefiles [GB|r]     # 0 = off

downloads-sorter on|off          # enable/disable the whole sorter
```

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

Create `~/.downloads-rules.conf` to override the built‑in categories:

```
# pattern              destination
*statement*         -> Documents/Finance
*.dwg               -> 3D & CAD
*figma*             -> Design
```

The arrow may be `->` or `→`; `#` lines are comments. Rules are checked **before** the built‑in categories. List them with `downloads-sorter rules`.

---

## Safety

- **Never deletes or overwrites.** Moves use a no‑clobber strategy and add ` (2)` on a name clash.
- **Everything is logged** to `~/Library/Logs/organize-downloads.log`.
- **Undo** reverses the most recent run.
- The 30‑day archive only **moves** files (into `Archive/`) — it never removes them, and the aging nudge only *reminds* you.

---

## How it works (under the hood)

- A per‑user **launchd agent** runs the sorter when `~/Downloads` changes (`WatchPaths`) and hourly as a backup (`StartInterval`), at low `Background` priority.
- The agent runs a small **AppleScript app** (`OrganizeDownloads.app`) instead of bare `bash`, because macOS grants *Downloads* access to an app identity, not to a raw shell. A separate `DownloadsNotifier.app` posts notifications (a bare `osascript` notification under launchd is silently dropped — it has no app identity to register).
- The actual logic is two plain‑bash scripts in `~/Library/Scripts`: `organize_downloads.sh` (the sorter) and `downloads-sorter` (the menu/CLI).

---

## Uninstall

```sh
./uninstall.sh
```

Removes the scripts, helper apps, launch agent, and settings. **Your sorted files and folders in `~/Downloads` are left exactly as they are.**

---

## Requirements

macOS (uses `launchd`, `osacompile`, `ditto`, `mdls` — all built in). No Homebrew or other dependencies required.

## License

MIT — see [LICENSE](LICENSE).
