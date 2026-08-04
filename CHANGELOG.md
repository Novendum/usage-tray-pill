# Changelog

All notable changes to Usage Tray Pill will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project intends to use [Semantic Versioning](https://semver.org/spec/v2.0.0.html) after its first public release.

## [Unreleased]

### Added

- Compact Windows 11 taskbar usage pill with click-only provider switching.
- ChatGPT/Codex, Claude, Antigravity, OpenCode Go, and Qwen Token Plan adapters.
- Hidden startup, desktop and Start-menu shortcuts, fullscreen hiding, and controlled helper shutdown.
- Local DPAPI protection for opt-in OpenCode Go and Qwen dashboard sessions.

### Changed

- Migrated the Windows interface and maintainer diagnostics to English.
- Improved the native WinForms main window and fractional-DPI taskbar-pill layout.
- Prefer fresh Claude Desktop usage when the Claude Code statusline snapshot is unavailable or stale.
- Clarified the experimental dashboard sources, refresh behavior, and encrypted credential storage for OpenCode Go and Qwen.
- Replaced the organization-licensed Gitleaks action with the pinned, checksum-verified open-source Gitleaks CLI in CI.

### Security

- Network destinations are explicitly restricted per provider adapter.
- Optional dashboard credentials are never read from provider-owned or browser credential stores.
- GitHub Actions includes PowerShell 5.1 tests and full-history secret scanning.
