# Changelog

All notable changes to Usage Tray Pill will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project intends to use [Semantic Versioning](https://semver.org/spec/v2.0.0.html) after its first public release.

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
