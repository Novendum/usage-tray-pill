# Changelog

All notable changes to Usage Tray Pill will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project intends to use [Semantic Versioning](https://semver.org/spec/v2.0.0.html) after its first public release.

## [0.1.0-rc.12] - 2026-10-24

### Added

- **Choose which limits the pill shows.** The **Pill** tab lists every provider with a check box per limit, such as **5-hour** and **Weekly**, with a live preview. Turn off what does not apply to you, for example the weekly limit of a Claude Team plan, which has none. Hidden limits also stay out of **Tightest window only** and the alerts; the quick view still shows everything. The last limit of a provider stays on. Your rc.11 choice for the ChatGPT / Codex 5-hour limit carries over.

### Changed

- A tighter pill with reset clocks. A limit you have not used yet (100% left) no longer shows a clock: ChatGPT and Claude move its reset along with every refresh, so it stood still at `5h` or `7d`. The quick view no longer promises a reset for it either.
- Each clock now keeps only the room its own kind of time needs, such as `3m`, `2h10m` or `6d5h`, instead of always the room for `0h00m`. The pill still keeps its width while the time ticks down and narrows once when a limit enters its last hour.

### Fixed

- At the smallest overview size, the hint at the bottom no longer runs under **Hide**, and the **Pill** tab no longer shows a needless horizontal scroll bar.

## [0.1.0-rc.11] - 2026-10-23

### Added

- **The ChatGPT / Codex 5-hour limit in the pill.** Plans with a 5-hour limit, such as ChatGPT Plus, now show it before the weekly limit, with one provider and with two. The optional reset clock and low-allowance alerts cover it too. To keep only the weekly limit, turn off **Show the ChatGPT / Codex 5-hour limit when your plan has one** in the **Pill** tab. Plans without a 5-hour limit look as before.

### Changed

- With **Tightest window only**, ChatGPT / Codex now weighs its 5-hour limit against the weekly one and shows whichever has the least left. A used-up weekly limit therefore still wins over a full 5-hour window.

### Fixed

- Countdown tests no longer fail on a PC whose clock changes for daylight saving time within the next three days.

## [0.1.0-rc.10] - 2026-10-20

### Fixed

- The experimental Claude CLI source finds the Claude Code that current Claude Desktop builds keep in `%LOCALAPPDATA%\Claude-Data`. Without it, UTP fell back to an older `claude.exe` on PATH and showed **CLI sign-in / setup required**.

## [0.1.0-rc.9] - 2026-10-20

### Changed

- Right-click the pill to open the quick view; middle-click still works too. The new **⋯** button in the quick view opens the full menu (setup, updates, resets, Exit). The tray icon and Shift+right-click on the pill open that menu directly.

### Fixed

- The quick view no longer closes the moment it opens. After a click on the taskbar pill, Windows often moves focus away again, and the quick view closed on that. It now stays open until you click outside it, press Esc or right-click the pill again.
- Quick view actions such as setting up OpenCode Go now start after the click has finished, so the panel never closes in the middle of its own click.

## [0.1.0-rc.8] - 2026-10-20

### Added

- **Quick view**: middle-click the pill, or choose **Quick view** in the tray menu, for a small panel with every provider's allowance windows, when each one resets and what needs your attention. It has **Refresh now** and **Open overview**; Esc or a click elsewhere closes it.
- **Notifications**, off by default: a Windows notification when an allowance window drops below 5, 10, 20 or 25%, and optionally when a limit resets. Turn them on in **Preferences**. Each window warns once until it recovers, and a restart does not repeat old warnings.
- **Check for updates** in **Preferences** and the tray menu. Only when you click it, UTP asks GitHub for a newer release of this project, checks the download against the release's SHA-256 checksum, keeps your current version as a backup, and restarts. Your settings stay. Copies that run from a Git checkout are never replaced.
- **Weekly countdown**: an optional clock for weekly and monthly windows in the two-provider pill, in days, for example `3d` or `2d5h`. Turn it on in the **Pill** tab next to the 5-hour countdown.
- **Clear sign-in and key status**: when a provider needs you (expired key, sign-in or setup), its logo in the pill gets a small red dot, and the quick view says what to do in a few words.

### Changed

- New app icon. UTP windows now show it instead of the PowerShell icon and get their own taskbar group.
- The overview window and its dialogs follow the Windows app mode, including a dark title bar in dark mode.
- OpenCode Go: when the `OPENCODE_GO_API_KEY` Windows variable is set, the setup dialog shows which key UTP uses and can switch to the key saved in UTP. Saving a new key switches to it. An expired key is reported as **API key expired**, with what to do.

### Upgrade notes

- Run `scripts\Install-StartMenuShortcut.ps1` once after installing this version. Windows then shows notifications and the taskbar group under the name Usage Tray Pill. Existing shortcuts keep working without it.
- **Check for updates** contacts `api.github.com` and GitHub's release-download host, and only when you click it. UTP never checks in the background.

## [0.1.0-rc.7] - 2026-10-16

### Added

- Optional reset countdown in the two-provider pill: a small clock and the time until the 5-hour limit resets, for example `5h 61% · 2h10m` or `40m`. Turn it on in the **Pill** tab. It rounds up, updates every minute, keeps the pill width stable and is never shown for cached or unknown values.

### Fixed

- Keep the background collector running when reporting a provider failure or saving a source schedule fails. Previously such a secondary error could stop the worker and with it collection for every provider until UTP restarted it. Pauses and safety rules are unchanged.
- Make the provider-recovery regression test immune to concurrent file access, and add a check that a failing failure report never stops the collector.

## [0.1.0-rc.6] - 2026-10-10

### Added

- Show two providers side by side in the pill, for example ChatGPT and Claude. Choose the layout, the left and right provider, and whether each side shows all allowance windows or only the tightest one in the new **Pill** tab, with a live preview. Right-click > **Show two providers** toggles the layout.
- In two-provider mode, click the left or right side of the pill to switch only that side. Sides never show the same provider, and a paused provider keeps its saved side.

### Changed

- Two-provider labels shorten to `5h`, `wk` and `mo` and are measured without GDI padding, so both providers fit in one capsule at every DPI. The single-provider pill is unchanged and stays the default.

### Upgrade notes

- Exit UTP and replace the complete application folder. Existing settings keep the single-provider pill until you choose two providers.

## [0.1.0-rc.5] - 2026-10-07

### Changed

- Organize application code in `src/`, developer tests in `tests/`, and optional installation/removal scripts in `scripts/`, with one root start file.
- Add a dedicated users' ZIP built from an explicit runtime file list, with checksums and a short user guide; exclude development tests, build tools and promotional media.
- Safely migrate this installation's legacy shortcuts and Claude statusline paths without overwriting unrelated integrations.
- Isolate test data from the user's profile and verify the clean package after extraction to a path with spaces.

## [0.1.0-rc.4] - 2026-10-04

### Fixed

- Stop Antigravity quota checks from launching its background updater and flashing Windows Terminal. The override applies only to UTP's AGY child processes.
- Preserve eligible Claude quotas after temporary failures with a visible cache label, a ten-minute limit and independent reset-time expiry. Authentication and safety failures still clear values and pause collection.
- Keep other providers running when one refresh times out. Preserve retry deadlines and safety pauses across collector restarts.
- Bind OpenCode Go and Qwen cached quotas to the active credential configuration; prevent stale account data from surviving a connection change.
- Own CLI process trees before provider code starts and clean up descendants on timeout, early return and exit.
- Preserve full-screen hiding by default, exclude desktop and other-monitor windows, and redraw the latest theme and quota data when the pill returns.
- Hide expired Claude statusline values, correctly detect an existing optional keeper, and label disabled providers in Details.

### Changed

- Refresh successful Claude CLI quotas every three minutes; wait at least five minutes when an eligible account returns no quota data, with retries capped at fifteen minutes.
- Add a full-screen hiding preference and regression coverage for independent refreshes, credential changes, persistent pauses, process ownership, child-only environment overrides and hidden-window redraws.

### Upgrade notes

- Replace the complete application folder after exiting UTP. Settings and saved connections stay in the user's application-data directory.
- Old OpenCode Go/Qwen caches without a credential revision remain unknown until the next successful read. Existing provider safety pauses are retained; use **Refresh now** after resolving a sign-in or setup issue.

## [0.1.0-rc.3] - 2026-10-02

### Fixed

- Retry unverifiable Claude CLI quota responses with bounded backoff instead of leaving collection permanently paused. Claude Desktop does not need to remain open for the CLI source.
- Keep authentication/setup failures and unexpected model or transcript activity paused; never display unverified values.
- Start background test helpers without creating console windows, removing a possible source of PowerShell flashes during testing.

### Verification

- Regression fixtures cover malformed-response recovery, retry bounds and unsafe-activity pauses. Existing UTF-8 handshake regressions remain intact.

## [0.1.0-rc.2] - 2026-10-02

### Added

- Refreshed README, provider setup guide, generated launch artwork and real fixture-based light/dark screenshots.
- Optional Claude CLI quota source and the Antigravity CLI usage adapter.

- Compact Windows 11 taskbar usage pill with click-only provider switching.
- ChatGPT/Codex, Claude, Antigravity, OpenCode Go, and Qwen Token Plan adapters.
- Hidden startup, desktop and Start-menu shortcuts, fullscreen hiding, and controlled helper shutdown.
- Local DPAPI protection for the opt-in OpenCode Go key and Qwen dashboard session.

### Changed

- Reuse one collector process and the Codex app-server connection; update the UI on quota-file changes and offer a Codex allowance selector.
- Read OpenCode Go's JSON usage API with a user-configured Go key; preserve old encrypted credentials until explicitly replaced.
- Pause providers after authentication/entitlement errors, apply bounded backoff and Retry-After, and refresh near known reset times.
- Keep Qwen's connection when disabled and expose a separate Preferences switch; remove the pill hover popup.
- Preserve fractional usage throughout collection and show less than one percent as `<1%`.

- Follow the Windows taskbar light/dark theme automatically, with matching text and logo contrast, and increase spacing from the notification-area arrow.

- Redesigned the pill as an automatically themed capsule with bold, high-contrast text.
- Replaced the main usage table with provider rows and truthful allowance meters; retained raw data in Details and moved setup actions to Preferences.

- Refresh all network-backed providers in background workers with visible progress and bounded lifetimes.
- Queue rapid provider clicks, shorten transitions, respect Windows animation preferences, and remove hover instructions while retaining accessible status text.
- Keep tab actions visible at different window sizes and preserve row selection during refresh.

### Fixed

- Keep JSON control handshakes free of UTF-8 byte-order marks on Windows hosts whose default console writer emits them.

- Render pill text with the native Windows text engine and create provider icons at their final physical size, retaining smooth alpha edges.
- Accept Claude's valid null reset time for unused quota windows; retain all Antigravity buckets in Details and show the restrictive window per family in the pill.

- Render the capsule as one per-pixel-alpha Windows layer, eliminating stepped window-region corners and opaque child-control clipping.
- Keep the inactive provider logo completely outside the viewport at fractional DPI scales.

- Preserve settings on read/write failures; keep provider snapshots separate from manual data.
- Prevent lost Codex responses and incorrect missing-percentage or weekly-window interpretation.
- Clear expired usage and distinguish cached snapshots from current values.
- Retain the correct controls and live state in tray-menu and overview callbacks.

### Earlier changes

- Migrated the Windows interface and maintainer diagnostics to English.
- Improved the native WinForms main window and fractional-DPI taskbar-pill layout.
- Prefer fresh Claude Desktop usage when the Claude Code statusline snapshot is unavailable or stale.
- Clarified the experimental dashboard sources, refresh behavior, and encrypted credential storage for OpenCode Go and Qwen.
- Replaced the organization-licensed Gitleaks action with the pinned, checksum-verified open-source Gitleaks CLI in CI.

### Security

- Network destinations are explicitly restricted per provider adapter.
- Optional dashboard credentials are never read from provider-owned or browser credential stores.
- GitHub Actions includes PowerShell 5.1 tests and full-history secret scanning.
