# Architecture

## Runtime

`src/Start-UsageTrayPill.ps1` owns the WinForms tray icon, taskbar pill, settings, cache consumption, fullscreen detection, and shutdown lifecycle. `src/Start-UsageCollector.ps1` owns background quota collection. Runtime helpers remain together in `src/`; shared runtime assets live in the root `assets/` folder.

`src/Launch-UsageTrayPill.vbs` starts the main script without a visible console window. The root `Start-UsageTrayPill.cmd` launcher delegates to this file. Optional installers and uninstallers live in `scripts/`, with shared ownership checks for current and same-root legacy paths.

`tests/Test-UsageTrayPill.ps1` runs the development suite in disposable profile directories. `scripts/Build-ReleasePackage.ps1` uses an explicit allowlist for the user ZIP, retaining runtime code, setup helpers, required assets and licenses while excluding tests, CI, build tools and promotional media. Its user README comes from `docs/USER_GUIDE.md`.

`PillRenderer.cs` owns the pill's layered WinForms window and premultiplied-alpha bitmap presentation through `UpdateLayeredWindow`. Capsule curves, labels, and icons are composited onto the same surface. Offscreen controls retain layout metadata; the visible pill has no opaque child windows or binary window region. Native bitmap and device-context handles are released after each frame. Alpha coverage and idle-logo placement are tested at 100%, 125%, 150%, 175%, and 200% scaling.

One hidden collector process hosts persistent, separate PowerShell runspaces for Codex, optional Claude CLI control, Antigravity, OpenCode Go, and Qwen. Codex retains its stdio app-server connection between requests. Successful collection schedules the next request after 60 seconds, 120 seconds for Qwen, or 180 seconds for Claude. Disabled sources do not poll. `CollectorPolicy.ps1` pauses on authentication, setup, and entitlement failures; other failures back off exponentially from 30 to 900 seconds or honor a bounded `Retry-After` value. Claude's eligible-but-null quota response waits at least 300 seconds. Explicit refresh and credential changes can resume a paused source. Manual request tokens and per-source consumption markers prevent replay after collector restart.

`UsageFileMonitor.cs` watches UTP usage caches and Claude Desktop history. Managed callbacks flag changes; the UI consumes them on its 500 ms tick. Claude statusline writes therefore appear without waiting for a network polling interval. Provider-side reporting delays remain outside UTP's control.

Per-provider `collector-schedule-*.json` files preserve retry deadlines and pauses across collector restarts. Explicit refresh or a changed credential revision can resume collection; restarting another source does not clear these limits. OpenCode Go and Qwen caches carry a one-way revision of the active credential configuration so values from a previous connection are not displayed after replacement. No plaintext credential is stored in these records.

External CLI reads use `OwnedUsageProcess.cs`. The helper creates the process suspended without a console, assigns it to a private kill-on-close Windows job, and then resumes it. Only the three standard pipe handles are inherited. Ending a read closes the job, including descendants left behind by an exited CLI. Codex retains its separate persistent connection. A timed-out UI refresh no longer stops the shared collector or other pending sources.

The native helper supports a private Unicode environment block for child-only overrides. AGY reads set `AGY_CLI_DISABLE_AUTO_UPDATE=true` through this block, preventing its periodic background updater from opening a separate console. The parent environment and other providers' environments are not modified.

`RequestDeadline.cs` bounds each HTTP request to 15 seconds, including slow stream reads; socket and read timeouts remain 12 seconds. External CLI commands have a 30-second maximum plus a separate version check. The UI's 45-second manual-refresh watchdog may stop its owned collector if a refresh stalls. Workers write normalized usage snapshots, not settings.

Provider clicks queue the latest selection while a 220 ms transition finishes. Animation uses a monotonic clock, follows the Windows menu-animation preference, and defers saving the selection until the transition completes. Right-click offers Refresh now. Hover tooltips are disabled; the root accessibility name remains available. Tab actions are positioned from the actual page size, and background refresh preserves selected rows.

The live overview renders five native provider rows from the same normalized snapshots used by the pill. Remaining-allowance meters are empty for unknown or disabled data. Details retains the full table, while Preferences contains account-connection and local configuration actions with scrolling at the minimum outer window size. The visual direction is recorded in `DESIGN.md`.

Tray and pill rendering is state-diff driven. The periodic timer detects fullscreen and geometry changes, but it does not recreate the notification icon, redraw unchanged quota content, or reassert topmost z-order. This keeps the Windows notification-area overflow and context menu stable while UTP is running.

The pill hides during full-screen taskbar coverage by default. The full-screen hiding preference uses `BadgeVisibility.cs` to sample actual primary-taskbar coverage outside the pill and can be disabled explicitly. Desktop windows, exposed taskbar regions, and apps on other monitors do not trigger hiding. Two agreeing samples are required for a visibility change; unknown native reads preserve the current state.

Claude's optional CLI source retains verified quota windows after transient failures for at most ten minutes from the last successful read. Reset times expire windows independently. The pill marks these values as cached and the overview shows the observation time. A cached result still counts as a failed fetch for retry scheduling; authentication, setup, or unexpected model/transcript activity clears values.

Windows Explorer can move its own topmost taskbar window above the pill after taskbar interaction. The geometry-only keepalive samples the pill center with `WindowFromPoint`. It restores z-order only when another root window actually covers that point, uses `SWP_NOACTIVATE`, pauses while UTP's menu is open, and applies a cooldown to prevent z-order storms.

## Provider inputs

ChatGPT/Codex usage uses `account/rateLimits/read` over the persistent local `codex app-server --stdio` connection. All returned limit buckets remain distinct; `codexLimitId` stores the selected bucket. Percentages remain floating-point values, and positive values below one percent display as `<1%` rather than zero.

Claude's default source remains its Code statusline payload, with Desktop usage history as a fallback. The optional isolated CLI diagnostic in `ExternalUsageAdapters.ps1` initializes a control session and sends `get_usage` with `skip_behaviors`, without a user prompt or model request. Unsupported account context and unexpected model activity fail closed. The initial signed-out probe returned `unsupported_auth_context`; signed-in CLI 2.1.286 subsequently returned verified quota windows with no model activity. The source is explicitly enabled in Preferences. UTP does not read Claude credentials.

Antigravity uses an installed CLI's `-p /usage --output-format json` command through `ExternalUsageAdapters.ps1`. The invocation is based on the [provider changelog](https://antigravity.google/docs/changelog/); the JSON contract is observed in [SigNoz's integration](https://signoz.io/docs/antigravity-cli-monitoring/) and [Heddle's usage-tap notes](https://github.com/mmayasaurus/heddle-dashboard/blob/main/docs/USAGE_TAP.md), not a published Google schema. The parser validates fields strictly and normalizes model groups conservatively. Missing CLI installation produces `setup_required`. CLI 1.2.14 was validated locally on 2026-10-02 with four quota windows and zero model turns. The old language-server loopback and CSRF path has been removed.

`OpenCodeGo.ps1` uses the [official `GET /zen/go/v1/usage` endpoint](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts) with an explicitly supplied Bearer key. It maps `usage.rolling`, `weekly`, and `monthly` to the existing normalized windows while preserving fractional percentages, status, and absolute resets. HTTP 401 maps to `auth_expired`, 403 to `subscription_required`, and 429 retains a bounded retry delay. Transient failures may retain cached values for up to six hours; authentication and entitlement failures hide them.

OpenCode credentials use version 2 of UTP's current-user DPAPI file. `OPENCODE_GO_API_KEY` takes precedence. Legacy version-1 cookie records yield `api_key_required` without decryption or modification; only an explicit save replaces the record. Disable preserves credentials and cache. No external key discovery is implemented.

The Qwen adapter is disabled until the user explicitly supplies a Cookie request-header value from the signed-in QwenCloud dashboard. It encrypts that value with current-user Windows DPAPI and uses it only for the exact `home.qwencloud.com` identity route and `cs-data.qwencloud.com` Token Plan gateway. Redirects are disabled, response size and time are bounded, and the fixed parser accepts only fractional consumed values for the 5-hour and weekly windows. UTP does not inspect Qwen CLI configuration, API keys, or browser-owned cookie storage.

The Preferences checkbox changes Qwen collection state while preserving its encrypted session and cache. Newer Personal-plan variants and the separate QwenCloud CLI require an account-specific compatibility check before changing the adapter; Coding Plan, Personal Token Plan, Team Token Plan, and Qwen Code OAuth are not interchangeable.

OpenCode Go and Qwen enforce response-size limits while reading the network stream. External CLI stdout and stderr are also bounded. No dependency installation is performed automatically.

## Local state

UTP owns `%APPDATA%\UsageTrayPill`. Provider-owned usage caches are external read-only inputs; provider credential stores are not read. `opencode-go-credentials.json` and `qwen-token-plan-credentials.json` are UTP-owned and contain DPAPI ciphertext plus format metadata.

Loading settings never writes or resets `data.json`. Invalid or unreadable settings stop startup with the original file intact. Codex workers write `codex-usage.json`; the UI imports only usage data, so a worker cannot overwrite settings or reset notes. Codex snapshots expire after 15 minutes and individual windows expire at their reset time. A missing percentage stays unknown, and window labels follow their actual duration. Claude observations are not made newer by payloads without quota data. OpenCode and Qwen retained snapshots are marked as cached after five minutes, rendered in a neutral color, and unavailable after six hours or expired authentication; reset windows are cleared independently.

## Process ownership

The main tray process may start a Claude keeper helper when explicitly enabled. Shutdown matches that helper by script path and command line before stopping it. Runtime cleanup is exception-safe and disposes all owned timers, windows, icons, mutex handles, and helper processes. Unrelated PowerShell, Claude, ChatGPT, database, and development processes are outside UTP's ownership boundary.

The security assumptions behind these boundaries are maintained in [THREAT_MODEL.md](THREAT_MODEL.md).

The pill text uses native GDI rendering on opaque temporary surfaces and copies glyph colors only into fully opaque capsule pixels; antialiased alpha edges remain unchanged. Icons are generated at final physical dimensions. The optional Claude CLI source uses `claude-control-usage.json`, remains disabled by default, and is selected explicitly in Preferences. Local signed-in checks on 2026-10-02 validated Claude Code 2.1.286 and Antigravity CLI 1.2.14 without model turns.
