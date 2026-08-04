# Architecture

## Runtime

`Start-UsageTrayPill.ps1` owns the WinForms tray icon, taskbar pill, local state, provider polling, fullscreen detection, and shutdown lifecycle.

`Launch-UsageTrayPill.vbs` starts the main script without a visible console window. The CMD launcher delegates to this file.

Tray and pill rendering is state-diff driven. The periodic timer detects fullscreen and geometry changes, but it does not recreate the notification icon, redraw unchanged quota content, or reassert topmost z-order. This keeps the Windows notification-area overflow and context menu stable while UTP is running.

Windows Explorer can move its own topmost taskbar window above the pill after taskbar interaction. The geometry-only keepalive samples the pill center with `WindowFromPoint`. It restores z-order only when another root window actually covers that point, uses `SWP_NOACTIVATE`, pauses while UTP's menu is open, and applies a cooldown to prevent z-order storms.

## Provider inputs

ChatGPT/Codex usage is read from a locally started Codex app-server process. Claude 5-hour and weekly values are accepted through Claude Code's statusline payload and may fall back to Claude Desktop's local history cache. Antigravity quota values are read from the loopback-only language server owned by the running Antigravity process. Optional OpenCode Go values are read from the signed-in workspace dashboard by `OpenCodeGo.ps1`. Optional Qwen Token Plan values are read from the signed-in QwenCloud dashboard session by `QwenTokenPlan.ps1`.

Claude usage is accepted only from Claude Code's statusline payload or Claude Desktop's local usage history. UTP does not read Claude credentials or call a Claude usage endpoint itself.

The Antigravity adapter validates the language-server executable shape, Antigravity-specific command arguments, process-owned loopback ports, and the exact local status endpoint. It normalizes model rows into at most three conservative family groups and discards all account fields before caching. Its temporary CSRF value remains memory-only. No Antigravity cloud fallback is implemented.

The OpenCode Go adapter is disabled until the user explicitly configures it. It accepts a workspace ID or dashboard URL and a dashboard `auth` cookie, encrypts the cookie with current-user Windows DPAPI, and sends it only to the matching HTTPS dashboard route. It parses 5-hour, weekly, and monthly windows from the embedded dashboard state. Network, server, parser, and rate-limit failures may retain a last-known snapshot for up to six hours; missing or expired authentication clears displayed values. UTP never discovers this credential from OpenCode or browser-owned files.

The dashboard compatibility approach was independently implemented after comparing the public MIT-licensed `agent-limits`, `opencode-quota`, and `opencode-bar` projects. They are compatibility references, not runtime dependencies:

- <https://docs.rs/crate/agent-limits/latest>
- <https://github.com/slkiser/opencode-quota>
- <https://github.com/opgginc/opencode-bar>

The Qwen adapter is disabled until the user explicitly supplies a Cookie request-header value from the signed-in QwenCloud dashboard. It encrypts that value with current-user Windows DPAPI and uses it only for the exact `home.qwencloud.com` identity route and `cs-data.qwencloud.com` Token Plan gateway. Redirects are disabled, response size and time are bounded, and the fixed parser accepts only fractional consumed values for the 5-hour and weekly windows. UTP does not inspect Qwen CLI configuration, API keys, or browser-owned cookie storage.

OpenCode Go, Qwen, and Antigravity enforce their response-size limits while reading the network stream. This prevents an oversized or malformed response from being fully allocated before rejection.

## Local state

UTP owns `%APPDATA%\UsageTrayPill`. Provider-owned credential and cache files are external read-only inputs. `opencode-go-credentials.json` and `qwen-token-plan-credentials.json` are UTP-owned and contain only the required identifiers plus DPAPI ciphertext.

## Process ownership

The main tray process may start a Claude keeper helper when explicitly enabled. Shutdown matches that helper by script path and command line before stopping it. Runtime cleanup is exception-safe and disposes all owned timers, windows, icons, mutex handles, and helper processes. Unrelated PowerShell, Claude, ChatGPT, database, and development processes are outside UTP's ownership boundary.

The security assumptions behind these boundaries are maintained in [THREAT_MODEL.md](THREAT_MODEL.md).
