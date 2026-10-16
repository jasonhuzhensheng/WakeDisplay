# WakeDisplay — working notes for Claude / 项目协作约定

macOS menu-bar utility (Swift/AppKit, LSUIElement). Author: Jason Hu 胡震生 (大老二), X @HUZHENSHENG. User communicates in Chinese; keep replies concise, with tables.
License: GPL-3.0-or-later. The name and logo are reserved (see `TRADEMARKS.md`).

## Branches & release rules (important)
- `main` = released code. `test` = work in progress. **Never release unless the user says "正式发布".**
- Release = bump `VERSION` in `build.sh` **and stage/commit it** → merge `test` into `main` → push. The release workflow builds only if that VERSION tag is new, creates the GitHub release, then a bot pushes the `Cask: vX` commit (run `git pull --rebase` afterwards; the tree must be clean).
- Merging code to `main` without a VERSION bump does not release (workflow says skipped).
- Pushing to `test` runs the Test build CI (macOS VM): build, smoke test in en + zh-Hans, size + startup metrics, screenshots. Results are force-pushed to the `test-results` branch (`git clone -b test-results`): `summary.txt`, PNGs, `build.log`, `linkmap.txt`, `desktop.png`.

## Build
- `./build.sh` builds, ad-hoc signs and installs. CI uses `SKIP_INSTALL=1`; `LINK_MAP=1` writes a link map; `TRACE=1` adds `-D TRACE` startup timing.
- Size/idle budget: download ≈ 167 KB zip, binary ≈ 327 KB, ~7 MB footprint, 0% idle CPU. Do not add dependencies or reflection-heavy code; keep timers coalesced.

## i18n
Edit `tools/i18n/translations.py` (KEYS + 15 language lists) → run `python3 gen.py` (in `tools/i18n`, in a scratch copy) → copy `Localization.swift` and `L10n.bin` to the repo root. `Localization.swift` is generated: never edit by hand. `build.sh` copies `L10n.bin` and `AppIcon.icns` into `Contents/Resources`.

## Code map
- `main.swift`: AppDelegate, menu (`buildMenu`: level 1 = Wake, Outdoor, 🎨 Display Mode, ⚙️ Advanced, Share), OutdoorMode, per-screen Display Modes (`ScreenMode`, `EInk`), hover-to-wake, icon drawing.
- `Advanced.swift`: ⚙️ Advanced submenu, DDC/brightness/volume/input, refresh rate, layout presets (`QuickLayout`), soft-disconnect.
- `Telemetry.swift`, `Updater.swift`, `Extras.swift`, `AutoOutdoor.swift`: anonymous stats, update check, crash report / reminder HUD, light-sensor auto outdoor.
- Startup order: status item first; heavy work deferred (next run-loop turn, +1 s, +5 s, +60 s).

## Sandbox limits (cloud session)
GraphQL `gh` commands (release view/download) are blocked, use `gh api` REST. Deleting releases/tags and setting repo topics must be done by the user. v1.28 was released by mistake and still exists.

## Open items
Developer ID signing + notarization (needs the user's Apple account and GitHub Secrets: DEVELOPER_ID_P12, DEVELOPER_ID_P12_PASSWORD, DEVELOPER_ID_NAME, NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD); trademark registration (IMPI); sponsor links; optional Pro edition; promotion posts (awesome lists, Reddit, Show HN, V2EX, AlternativeTo); verify "All Screens Black & White" on a real Mac.
