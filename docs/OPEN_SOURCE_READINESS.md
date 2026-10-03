# Release readiness

## v0.1.0-rc.4 — stability update

Prepared on 2026-10-04 from the public rc.3 baseline. This candidate carries the tested local stability fixes onto the existing public history.

### Verified locally

- The complete Windows PowerShell 5.1 suite covers provider parsing, cache expiry, account changes, retry deadlines, independent refreshes, fullscreen visibility, rendering and interactions.
- New regressions cover corrupt schedule files, locked credential files, account changes during failure handling, nested Windows jobs, handle isolation and child-only Unicode environment overrides.
- Signed-in Codex, Claude Code 2.1.286, Antigravity CLI 1.2.14 and OpenCode Go produced current quota data after local activation. Qwen remained disabled.
- A Windows Terminal flash was traced through its client process handle to an AGY descendant of UTP. The AGY update-status file changed immediately afterward. With auto-update disabled only for UTP's AGY children, a seven-minute observation recorded 14 direct AGY starts, no nested AGY updater starts and no console-window events. Quota reads continued beyond the updater's normal fifteen-minute check interval.
- Fullscreen hiding remains enabled by default. No global provider or Windows Terminal settings were changed.

### Publication gates

The candidate must pass both required GitHub checks before merging. Build the release ZIP from the merged commit, extract it to a path containing spaces, run the complete suite again and scan the package and Git history. Publish its SHA-256 checksum with the archive, then verify the public download. Record the exact commit and final package checks in the [release notes](https://github.com/Novendum/usage-tray-pill/releases/tag/v0.1.0-rc.4).

### Remaining validation limits

- Full manual OpenCode Go setup, expired-key, subscription and cross-user DPAPI scenarios.
- Qwen plan/session variants; it is optional and disabled by default.
- A fresh Windows user, multiple physical monitors and DPI transitions.
- Long-duration stability across Windows and provider upgrades.

These are not claims of universal compatibility. Keep rc.4 marked as a prerelease. Fixtures and one maintainer machine cannot establish every account/device combination.

## Earlier releases

- [rc.3](https://github.com/Novendum/usage-tray-pill/releases/tag/v0.1.0-rc.3): Claude quota recovery and hidden test helpers.
- [rc.2](https://github.com/Novendum/usage-tray-pill/releases/tag/v0.1.0-rc.2): redesigned pill, persistent collection and provider updates.
- [Historical August readiness record](https://github.com/Novendum/usage-tray-pill/blob/814714061b7f8d23f1f3346db940e195e5778c62/docs/OPEN_SOURCE_READINESS.md).

Preserve the public Git history. Never replace it with a local clean-root checkout.
