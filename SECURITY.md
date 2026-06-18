# Security Policy

Thanks for helping keep **Downloads Sorter** and its users safe.

## Supported versions

This is a single‑track, rolling release: only the **latest version** is supported.
If you're not current, update before reporting:

```sh
dsort update     # installs the latest verified version
dsort version    # shows what you have
```

| Version | Supported |
|---|---|
| Latest (`main` / newest release) | ✅ |
| Anything older | ❌ — please `dsort update` first |

## Reporting a vulnerability

**Please do _not_ open a public issue for security problems.**

Report privately through GitHub's **Private vulnerability reporting**:

> Repo **Security** tab → **Report a vulnerability** → fill in the advisory form.

(Direct link: `https://github.com/Lucid06-K/mac-downloads-sorter/security/advisories/new`)

Please include:

- what you found and where (file + line, or the relevant `dsort` command / menu path),
- steps to reproduce, or a minimal proof of concept,
- the impact you think it has, and
- your `dsort version` and macOS version.

**What to expect:**

- **Acknowledgement:** within ~7 days.
- **Assessment & fix:** for a confirmed issue, a patch is shipped on `main` (delivered to users via `dsort update`) as quickly as is practical, and the advisory is published once a fix is available.
- **Credit:** you'll be credited in the advisory unless you'd prefer to stay anonymous.

If you can't use GitHub private reporting, open a normal issue titled **"security — please contact me"** with **no technical details**, and a maintainer will arrange a private channel.

## Scope

Most relevant areas to look at:

- **The auto‑updater** (`dsort update` / opt‑in auto‑update) — the only part that fetches and runs remote code.
- **The launchd agent** and the helper apps (`OrganizeDownloads.app`, `DownloadsNotifier.app`).
- **File handling** in the sorter (moves, the undo history, empty‑folder cleanup).

Out of scope: issues that require an already‑compromised user account or physical access; social‑engineering of the user; and anything in third‑party tools you run alongside it (e.g. Syncthing).

## Security design (what's already in place)

The project is built to be conservative by default:

- **Runs entirely in user space — never `sudo`**, nothing system‑wide.
- **Never deletes your files.** Moves are no‑clobber; only empty folders and disposable junk (`.DS_Store`, orphaned `~$…` locks) are ever removed, and every move is logged and undoable.
- **Updates are signed and verified:** the checksum manifest is verified against an **RSA‑3072 signature** made with the maintainer's **offline** key (checked with the public key baked into your installed copy) *before* anything is touched — so a compromise of GitHub, the CDN, or TLS alone cannot push code. Each file is then matched against the signed **SHA‑256 checksums**, **syntax‑checked** (`bash -n`), and the previous scripts backed up to `*.bak`. Fetched **over HTTPS only**, pinned to this repository (redirects forced to HTTPS). Auto‑update is **off by default**. Verification uses macOS's built‑in `openssl` — no extra dependency. See [SIGNING.md](SIGNING.md).
- **No `eval`**; untrusted inputs (filenames, download‑origin URLs, the activity log, config files) are handled as quoted data, never executed.
- **No network access** anywhere except the updater.

## Trust note

Update signing means a malicious repo/CDN/TLS can't push code without the maintainer's offline private key. The remaining trust assumptions are: (1) the **first install** — you're trusting the initial clone, since that's where your copy of the public key comes from; and (2) the maintainer's key custody. For a manual update you can always review the diff on GitHub first, and auto‑update is opt‑in for exactly these reasons.
