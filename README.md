<p align="center">
  <img src="assets/utp-logo.svg" width="72" alt="Usage Tray Pill logo">
</p>

<h1 align="center">Usage Tray Pill</h1>
<p align="center">Your AI usage, one glance away.</p>
<p align="center">
  <a href="https://github.com/Novendum/usage-tray-pill/actions/workflows/test.yml"><img src="https://github.com/Novendum/usage-tray-pill/actions/workflows/test.yml/badge.svg" alt="Tests and secret scan"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-172338" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/platform-Windows_11-2563eb" alt="Windows 11">
</p>

https://github.com/user-attachments/assets/1b7e8957-90d4-4648-955d-8c88aa771793

<p align="center"><sub>12-second tour, sound on · animated product illustration with illustrative values · <a href="docs/media/utp-promo.mp4">MP4 in this repository</a></sub></p>

A small Windows utility for checking remaining **Codex, Claude, Antigravity, OpenCode Go and Qwen Token Plan** allowances from your taskbar. Click to switch providers. Open the overview when you want the details.

**[Quick start](#quick-start)** · **[Provider setup](docs/PROVIDERS.md)** · **[What's changed](CHANGELOG.md)** · **[Report a bug](https://github.com/Novendum/usage-tray-pill/issues)**

## What's new in rc.8

**Everything at a glance, and a heads-up when it matters.** Middle-click the pill for the new **quick view**: every limit, when it resets, and which provider needs you. Turn on notifications for a low allowance or a reset, and update UTP from inside the app with **Check for updates**. UTP also gets a new icon, an overview that follows Windows dark mode, and a red dot on any provider that needs a new key or sign-in.

![Quick view in light and dark, showing illustrative ChatGPT, Claude and OpenCode Go values](docs/media/utp-quick-view.png)

Earlier: rc.7 added a **reset countdown** to the two-provider pill, and rc.6 added **two providers side by side**.

![Two-provider pill with a reset countdown in light and dark taskbars, showing illustrative values](docs/media/utp-reset-countdown.png)

[Download v0.1.0-rc.8](https://github.com/Novendum/usage-tray-pill/releases/tag/v0.1.0-rc.8) · [Read the changes](CHANGELOG.md#010-rc8---2026-10-20)

## At home in your taskbar

![Actual UTP pills in light and dark themes, showing illustrative Codex and Claude allowances](docs/media/utp-pill-themes.png)

- **A clear glance.** Bold text, smooth rounded edges and crisp icons. The pill follows your Windows taskbar's light or dark theme.
- **Two at a glance.** Show two providers side by side, such as ChatGPT and Claude. Set it up in the **Pill** tab of the overview, or right-click > **Show two providers**.
- **A quiet interaction.** Click to cycle providers, middle-click for the quick view, right-click for actions. No hover popup. Transitions respect Windows animation preferences.
- **A heads-up when it matters.** Optional notifications when an allowance runs low or a limit resets, and a red dot when a provider needs a new key or sign-in.
- **Predictable visibility.** The pill hides when a full-screen app covers the primary taskbar and returns when the taskbar is exposed. You can disable full-screen hiding in Preferences.
- **Freshness you can understand.** Background collection, refresh controls and explicit unavailable states. Missing data appears as `--`.
- **Your choice of sources.** Select the Codex allowance bucket and enable optional integrations in Preferences. Disable OpenCode Go or Qwen without losing the saved connection.
- **Local by design.** Settings and caches stay on your PC. No UTP account or telemetry service. Provider requests use the connections described in [Privacy](PRIVACY.md); UTP contacts GitHub only when you click **Check for updates**.

## A closer look

<p align="center">
  <img src="docs/media/utp-overview.png" width="49%" alt="UTP usage overview in light mode with illustrative remaining allowances and Qwen paused">
  <img src="docs/media/utp-overview-dark.png" width="49%" alt="The same overview in Windows dark mode">
</p>

The overview brings available allowance windows together, with separate Details, Pill and Preferences tabs, and follows the Windows light or dark app mode. These images use **fictitious values** rendered by the actual app; setup-required and paused providers are shown deliberately. The cover is generated product artwork with illustrative values, not a pixel-exact screenshot.

## Quick start

You need **Windows 11**, **Windows PowerShell 5.1**, and a supported, signed-in provider. Configure only the providers you use.

1. [Download the source ZIP](https://github.com/Novendum/usage-tray-pill/archive/refs/heads/main.zip) and extract the **whole folder**, or clone this repository.
2. Review the scripts, then double-click **`Start-UsageTrayPill.cmd`**.
3. Right-click the pill to open its menu, or middle-click it for the quick view. Open the overview and Preferences to choose your sources.

No administrator rights are required. Keep `src/`, `scripts/` and `assets/` beside the start file. The users' ZIP includes the app and optional setup helpers; development tests and promotional media stay in the source repository. See the [user guide](docs/USER_GUIDE.md) for upgrading from the older flat folder.

| Provider | What you need | Integration |
| --- | --- | --- |
| ChatGPT / Codex | Signed-in Codex CLI or compatible ChatGPT desktop installation | Local Codex app-server; selectable allowance bucket |
| Claude | Claude Code statusline integration, or Claude Desktop usage history | Optional CLI quotas are experimental and off by default |
| Antigravity | Separately installed, signed-in Antigravity CLI | Read-only `/usage` command; desktop app alone is insufficient |
| OpenCode Go | Go subscription and a Go API key you supply | Official usage endpoint; off by default |
| Qwen Token Plan | Compatible QwenCloud plan and dashboard session | Experimental dashboard adapter; off by default |

Follow the [provider setup guide](docs/PROVIDERS.md) for connection steps, migration notes and known limitations. A provider's absence does not require installing it just to try UTP.

<details>
<summary><strong>Optional shortcuts and startup</strong></summary>

Run only the installers you want from Windows PowerShell in the extracted folder:

```powershell
.\scripts\Install-DesktopShortcut.ps1
.\scripts\Install-StartMenuShortcut.ps1
.\scripts\Install-Startup.ps1
```

Claude's statusline integration is separate:

```powershell
.\scripts\Install-ClaudeStatusLine.ps1
```

Installers preserve unrelated shortcuts and existing statuslines. Use `-Force` only when you deliberately want to replace one. Claude settings changes create a backup.

If your execution policy blocks reviewed scripts, you can allow them for the current terminal session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

This does not change the permanent user or machine policy.

</details>

<details>
<summary><strong>Updating and uninstalling</strong></summary>

From rc.8 on, choose **Check for updates** in the tray menu or Preferences: UTP downloads the new release from GitHub, verifies its checksum, keeps your current version as a backup and restarts. To update an older version by hand, exit UTP before replacing its application files. For the new folder layout, back up the old application folder and extract into an empty folder at the same path. Do not overlay the new ZIP on old files. Re-run the optional installers you used to migrate their old root-level paths safely. See the [upgrade instructions](docs/USER_GUIDE.md#upgrade-from-the-old-flat-folder).

OpenCode Go users migrating from the dashboard adapter must supply a Go API key through setup. Old encrypted cookie records are preserved but no longer used.

Remove the optional integrations independently:

```powershell
.\scripts\Uninstall-Startup.ps1
.\scripts\Uninstall-DesktopShortcut.ps1
.\scripts\Uninstall-StartMenuShortcut.ps1
.\scripts\Uninstall-ClaudeStatusLine.ps1
```

Settings and caches remain in `%APPDATA%\UsageTrayPill`. Delete that directory yourself only if you also want to remove settings, notes and saved UTP connections.

</details>

## Status and limitations

UTP is a **public open-source release candidate**. The repository contains the source; provider compatibility can change independently of UTP. See the [readiness record](docs/OPEN_SOURCE_READINESS.md) for what was tested and what remains open.

Codex, Antigravity and OpenCode Go normally check once a minute; Claude CLI checks every three minutes and enabled Qwen every two minutes. Cache changes reach the UI on a 500 ms tick. These are polling intervals, not a promise of instant provider updates. Authentication errors pause collection, and temporary errors use bounded retry delays.

The [earlier demo](https://github.com/user-attachments/assets/1f7a0588-d80b-4f79-ab9f-c70e5b1f08a8) shows the original release-candidate design. The screenshots above represent the current code in this branch.

## Contribute

The repository separates application code, maintenance scripts and tests:

```text
Start-UsageTrayPill.cmd   Start here
src/                     App, collectors and native helpers
scripts/                 Optional setup, removal and package builder
tests/                   Development and regression checks
assets/                  Runtime icons and branding
docs/                    Guides, architecture and development notes
```

Bug reports, provider compatibility notes and focused pull requests are welcome. Please keep account data and credentials out of reports.

```powershell
.\tests\Test-UsageTrayPill.ps1
```

Run tests in **Windows PowerShell 5.1**. Tests cover provider parsing, refresh lifecycle, interaction, DPI rendering, notifications, updates and credential boundaries using isolated fixtures; passing offline tests does not prove every account or plan works.

[Contributing](CONTRIBUTING.md) · [Architecture](docs/ARCHITECTURE.md) · [Support](SUPPORT.md) · [Security](SECURITY.md) · [Privacy](PRIVACY.md)

## License and independence

UTP is unofficial and is not affiliated with or endorsed by the providers it displays.

Source: [MIT](LICENSE). The bundled Qwen Code indicator: [Apache-2.0](THIRD_PARTY_LICENSES/QWEN_CODE_APACHE-2.0.txt). Other runtime provider indicators come from installed applications, with a neutral fallback when absent. Names and trademarks belong to their respective owners. See [third-party notices](THIRD_PARTY_NOTICES.md) and [asset provenance](docs/ASSET_PROVENANCE.md).
