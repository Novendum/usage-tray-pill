# Repository Settings

Apply these settings while the repository is still private, then verify them again before changing visibility.

## Identity

- Owner namespace: `Novendum`
- Repository name: `usage-tray-pill`
- Display name: Usage Tray Pill
- Description: `A compact Windows 11 taskbar pill for viewing local AI provider usage limits.`
- Website: leave empty until a project website exists.
- Topics: `windows`, `powershell`, `system-tray`, `taskbar`, `usage-monitor`, `chatgpt`, `claude`, `qwen`, `opencode`
- Public support: [GitHub Issues](https://github.com/Novendum/usage-tray-pill/issues)
- Private vulnerability reports: [GitHub Security Advisories](https://github.com/Novendum/usage-tray-pill/security/advisories/new)

Provider names are discovery topics, not UTP branding or an endorsement claim.

## Features

- Enable Issues.
- Disable Wikis unless maintainers commit to keeping a second documentation source current.
- Enable Discussions only when there is capacity to moderate support conversations.
- Enable private vulnerability reporting before public release.
- Keep branch deletion after merge enabled.

## Default branch protection

Protect `main` after the clean release-candidate history is pushed:

- Require a pull request before merging.
- Require the `powershell-51` and `secret-scan` status checks.
- Require branches to be up to date before merging.
- Block force pushes and branch deletion.
- Require conversation resolution.

The first clean-history push is an exceptional maintainer operation. Protect the branch immediately afterward.

## Release

Do not attach `%APPDATA%\UsageTrayPill`, logs, credential files, provider responses, or account screenshots to a release.

Build the release archive from a clean checkout of the reviewed commit. Include only Git-tracked files and verify the archive with `Test-UsageTrayPill.ps1` and Gitleaks before publishing.
