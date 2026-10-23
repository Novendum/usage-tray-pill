# Usage Tray Pill

Your AI usage, one glance away.

## Start

1. Extract the **whole ZIP** to a folder you want to keep.
2. Review the scripts, then double-click **Start-UsageTrayPill.cmd**.
3. Click the pill to switch providers. Right-click it for the **quick view**: every limit, when it resets and what needs your attention. The **⋯** button in the quick view opens the menu with the overview, settings and Exit; Shift+right-click on the pill opens that menu directly.
4. Optional: show two providers at once, such as ChatGPT and Claude, in the overview's **Pill** tab. Then click the left or right side of the pill to switch that side. Turn on **Show time until the 5-hour limit resets** to see a small clock with the remaining time, such as `2h10m`, and **Also for weekly and monthly limits** to count those down in days, such as `3d`. A clock appears once you start using a limit; a limit with 100% left has nothing to reset yet.
5. Choose what the pill shows under **Limits in the pill** in the **Pill** tab: one check box per limit, per provider. Turn off what you do not need, such as the weekly limit of a Claude Team plan, which has none. Hidden limits get no alerts; the quick view still lists everything. With **Windows shown** set to **Tightest window only**, each provider shows just the shown limit with the least left.

Requires Windows 11 and Windows PowerShell 5.1. No administrator rights are needed. The pill follows the taskbar theme and hides during fullscreen by default.

Keep `src/`, `assets/` and `scripts/` beside the start file. You do not need to open the source files to use the app. Settings and saved connections live separately in `%APPDATA%\UsageTrayPill`.

## Connect providers

Use only the services you already have. Sign in with each provider's supported CLI or configure its optional connection in UTP. OpenCode Go, Qwen and the experimental Claude CLI source are off by default.

See [provider setup](PROVIDERS.md). Missing values appear as `--`; cached values are marked. A small red dot on a provider's logo means it needs you: sign in again, add a new key or finish setup. The quick view says which. Resolve those before using **Refresh now**.

## Notifications and updates

In **Preferences**, turn on **Notify when an allowance drops below** and choose 5, 10, 20 or 25% to get a Windows notification when a window falls under it. **Send test notification** shows what it looks like. Turn on **Notify when a limit resets** to hear when it is available again. Both are off by default.

**Check for updates** in Preferences or the tray menu asks GitHub for a newer release, and only when you click it. **Update now** downloads the release and checks its SHA-256 checksum. It then keeps your current version next to it as a backup (`...previous-<version>`) and restarts UTP. Your settings stay. To go back, exit UTP, rename the current folder, and give the backup the original folder name.

## Optional installation

Open Windows PowerShell in this folder and run only the options you want:

```powershell
.\scripts\Install-DesktopShortcut.ps1
.\scripts\Install-StartMenuShortcut.ps1
.\scripts\Install-Startup.ps1
```

The Start-menu shortcut also lets Windows show notifications and the taskbar group under the name Usage Tray Pill.

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
