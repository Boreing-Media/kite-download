# Kite download

Public page: **https://boreing-media.github.io/kite-download/** — Windows + Mac buttons, always the latest Kite.

- `index.html` — the page (GitHub Pages, `main` branch root).
- `Install-Takeoff.cmd` — one-file Windows install (13 Nov 2026): asks GitHub's API for the newest release, GitHub's own SHA-256 of `Takeoff-Windows.zip` and its `Takeoff-Windows.zip.sig`, downloads both, and unzips and runs "Make this PC reachable" only if the SHA-256 matches AND the zip carries a P-256 signature by Takeoff's update key (16 Nov 2026: the public key is written in the .cmd, never fetched; a revoked key, the old Ed25519 key, no signature or any mismatch = refused, download deleted). `Install-Takeoff.cmd check` = download + verify only; `Install-Takeoff.cmd verify ZIP SIG [SHA256]` = verify local files only. No `irm | iex` (Defender blocks that as Trojan:Win32/ClickFix).
- `Takeoff-Windows.zip.sig` (a release asset) — `{"signature_p256": "<hex r||s>"}`: ECDSA P-256 over SHA-256 of the zip's exact bytes, the same signature the PCs' own updater checks. Made by kite's `mac/public-release.sh` (the ship's one Touch ID).
- **A new or revoked update key** (kite `mac/update-key.sh make-se`): put it in `$TrustedP256` / `$RevokedP256` in `Install-Takeoff.cmd` too. `./release` refuses a zip those keys do not verify, and kite's `mac/public-release.sh` refuses while the .cmd trusts a key the hosts do not.
- `win.txt` — the old one-liner (`irm … | iex`), no longer on the page; still pinned by `./release` for anyone who saved it.
- `./release` — publish the newest `~/AppDevelopment/kite/out/Takeoff-Windows.zip` (+ its `.sig`, checked first) + `Takeoff-*.dmg` as the latest release.

Only installers live here; Kite's source stays in private `Boreing-Media/kite`.
