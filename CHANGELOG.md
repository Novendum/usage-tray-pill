# Changelog

All notable changes to Usage Tray Pill will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project intends to use [Semantic Versioning](https://semver.org/spec/v2.0.0.html) after its first public release.

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
