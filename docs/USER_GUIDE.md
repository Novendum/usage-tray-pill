# Usage Tray Pill

Your AI usage, one glance away.

## Start

1. Extract the **whole ZIP** to a folder you want to keep.
2. Review the scripts, then double-click **Start-UsageTrayPill.cmd**.
3. Click the pill to switch providers. Right-click it to open the overview, settings or Exit.

Requires Windows 11 and Windows PowerShell 5.1. No administrator rights are needed. The pill follows the taskbar theme and hides during fullscreen by default.

Keep `src/`, `assets/` and `scripts/` beside the start file. You do not need to open the source files to use the app. Settings and saved connections live separately in `%APPDATA%\UsageTrayPill`.

## Connect providers

Use only the services you already have. Sign in with each provider's supported CLI or configure its optional connection in UTP. OpenCode Go, Qwen and the experimental Claude CLI source are off by default.

See [provider setup](PROVIDERS.md). Missing values appear as `--`; cached values are marked. Resolve sign-in or setup errors before using **Refresh now**.

## Optional installation

Open Windows PowerShell in this folder and run only the options you want:

```powershell
.\scripts\Install-DesktopShortcut.ps1
.\scripts\Install-StartMenuShortcut.ps1
.\scripts\Install-Startup.ps1
```

Claude's optional statusline integration has its own installer:

```powershell
.\scripts\Install-ClaudeStatusLine.ps1
```

## Upgrade from the old flat folder

Exit UTP first. Back up your old application folder and extract into an **empty folder at the same installation path**. Do not merge the old files into the new layout: that would leave the old tests and scripts behind.

Run the installers again for the shortcuts and integrations you used. They recognize this installation's old root-level paths and migrate them to `src/`. If you choose a different installation path, remove the old integrations with their old uninstall scripts before installing the new ones. Existing shortcuts belonging elsewhere are protected unless you deliberately use `-Force`.

Your `%APPDATA%\UsageTrayPill` settings and connections stay intact.

## Remove optional integrations

```powershell
.\scripts\Uninstall-Startup.ps1
.\scripts\Uninstall-DesktopShortcut.ps1
.\scripts\Uninstall-StartMenuShortcut.ps1
.\scripts\Uninstall-ClaudeStatusLine.ps1
```

These commands remove only the selected integrations, not your saved UTP data. Exit UTP before removing its application folder.

## Help and source

[Support](../SUPPORT.md) · [Privacy](../PRIVACY.md) · [Security](../SECURITY.md) · [Changes](../CHANGELOG.md) · [Licenses and notices](../THIRD_PARTY_NOTICES.md)

The source repository and development tests are available at [Novendum/usage-tray-pill](https://github.com/Novendum/usage-tray-pill). This users' package deliberately excludes tests, build tools and promotional media.
