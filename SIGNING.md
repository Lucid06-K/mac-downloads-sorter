# Update signing (maintainer notes)

The auto-updater (`dsort update`) will only install a release whose `SHA256SUMS`
manifest carries a valid **RSA-3072 signature** from this project's key. The
checksums prove the files match the manifest; the signature proves the manifest
came from the maintainer. Together they mean a compromise of the GitHub repo,
the `raw.githubusercontent.com` CDN, or the TLS connection is **not enough** to
push code — an attacker would also need the offline private key.

Verification on the client uses macOS's built-in `openssl` (LibreSSL), so users
install nothing extra.

## Keys

- **Private key:** `~/.config/dsort/update.key` — RSA-3072, `chmod 600`, **never
  committed** (the repo `.gitignore` blocks `*.key`/`*.pem` as a backstop).
  **Back it up** in your password manager. If it's lost you can no longer ship
  verifiable updates and must migrate users via a fresh clone with a new key.
- **Public key:** embedded as the `UPDATE_PUBKEY` constant in
  `src/downloads-sorter`. The client verifies with **its own installed** copy of
  this key (trust-on-first-use), never a freshly downloaded one.

One-time generation (already done):

```sh
mkdir -p ~/.config/dsort && chmod 700 ~/.config/dsort
umask 077
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out ~/.config/dsort/update.key
chmod 600 ~/.config/dsort/update.key
openssl pkey -in ~/.config/dsort/update.key -pubout      # paste into UPDATE_PUBKEY
```

## Shipping a release

**Preferred:** use the release helper — it bumps both VERSIONs, syntax-checks,
regenerates **and signs** the manifest (refusing to proceed if the key is
missing/mismatched), syncs the live copy, and commits + pushes:

```sh
./release.sh --dry-run 1.0.34       # validate everything (incl. real signing) first
./release.sh 1.0.34 -m "fix: …"     # cut it: bump → sign → commit → push
./release.sh 1.0.34                 # or stop before commit so you can review
```

### Manual fallback (what release.sh does under the hood)

After you've finalised `src/`, bumped both VERSIONs, and synced the live copy,
regenerate **and sign** the manifest, then commit the `.sig` alongside it:

```sh
cd <repo>
( cd src && shasum -a 256 * > ../SHA256SUMS )                 # regenerate manifest
openssl dgst -sha256 -sign ~/.config/dsort/update.key \
    -out SHA256SUMS.sig SHA256SUMS                            # sign it
# sanity check before committing:
openssl pkey -in ~/.config/dsort/update.key -pubout 2>/dev/null > /tmp/dsort.pub
openssl dgst -sha256 -verify /tmp/dsort.pub -signature SHA256SUMS.sig SHA256SUMS   # → Verified OK
git add SHA256SUMS SHA256SUMS.sig src/ VERSION
git commit && git push
```

**Rule:** once a signed release is published (1.0.33+), **never publish an
unsigned manifest again** — the client treats a missing/invalid signature as a
hard failure. (Old clients ≤1.0.32 ignore the `.sig` and still update via
checksums, so the rollout doesn't strand anyone.)

## Rotating the key

If you must rotate (suspected key compromise, or routine hygiene):

1. Generate `update.key.new` and its public key.
2. In `src/downloads-sorter`, set `UPDATE_PUBKEY` to the **new** public key.
3. Sign that release's `SHA256SUMS` with the **OLD** key — installed clients
   still carry the old public key, so that's what they verify against. (If you
   sign with the new key, no existing client can verify it.)
4. Ship. Once the fleet has moved onto the release carrying the new public key,
   subsequent releases are signed with the new key.

To verify-during-transition you can temporarily support two keys client-side
(try new, then old), but for a tiny fleet the single old-key-signs-the-handoff
step above is simplest.
