# Kite download

Public page: **https://boreing-media.github.io/kite-download/** — Windows + Mac buttons, always the latest Kite.

- `index.html` — the page (GitHub Pages, `main` branch root).
- `Install-Takeoff.cmd` — one-file Windows install (13 Nov 2026): asks GitHub's API for the newest release and GitHub's own SHA-256 of `Takeoff-Windows.zip`, downloads it, refuses a mismatch, unzips, runs "Make this PC reachable". `Install-Takeoff.cmd check` = download + verify only. No `irm | iex` (Defender blocks that as Trojan:Win32/ClickFix).
- `win.txt` — the old one-liner (`irm … | iex`), no longer on the page; still pinned by `./release` for anyone who saved it.
- `./release` — publish the newest `~/AppDevelopment/kite/out/Kite-Windows.zip` + `Kite-*.dmg` as the latest release.

Only installers live here; Kite's source stays in private `Boreing-Media/kite`.
