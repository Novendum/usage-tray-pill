# Privacy

Usage Tray Pill is a local Windows utility. It has no UTP telemetry service, analytics service, advertising service, or UTP account system.

## Data stored by UTP

UTP stores settings, manual notes, cached usage percentages, reset timestamps, and local helper logs under `%APPDATA%\UsageTrayPill`. Normalized Antigravity quota data is stored in `antigravity-usage.json`; it contains no account identity or credential. Normalized OpenCode Go and Qwen quota data is stored in `opencode-go-usage.json` and `qwen-token-plan-usage.json`. Collector refresh-request and consumption markers also stay in this directory.

Normalized Codex usage is stored separately in `codex-usage.json`. Refresh workers do not write your settings or manual notes in `data.json`.

Per-provider collector schedule files store retry deadlines and pause state. OpenCode Go and Qwen caches and schedules also store a one-way revision hash of the active credential configuration to prevent reuse of another connection's quotas. These records contain no plaintext key or cookie.

When OpenCode Go is explicitly configured, version 2 of `opencode-go-credentials.json` contains the user-supplied API key encrypted with Windows DPAPI for the current Windows user. UTP does not write the plaintext key to disk. `OPENCODE_GO_API_KEY` can supply the key instead and takes precedence. Legacy version-1 cookie records are left intact without decryption or use until the user explicitly saves a replacement.

When Qwen Token Plan is explicitly configured, `qwen-token-plan-credentials.json` contains the user-supplied QwenCloud Cookie request-header value encrypted with Windows DPAPI for the current Windows user. The plaintext header is not written to disk by UTP.

Disabling OpenCode Go or Qwen preserves its credential and cache. Disabled Qwen collection sends no quota requests.

Do not include this directory in bug reports. Manual notes may contain information you entered yourself.

## Local data read by UTP

Depending on enabled features, UTP may read:

- the Windows process list to detect ChatGPT, Codex, Claude, Antigravity, fullscreen applications, and UTP-owned helpers;
- local ChatGPT/Codex installation paths to find an application icon;
- Claude Code statusline JSON sent directly to the configured UTP script;
- Claude Desktop's local `plan-usage-history.json` cache.
- installed CLI executable paths, versions, and bounded command output for supported external quota adapters;
- UTP's own DPAPI-encrypted OpenCode Go API key after the user explicitly saves it;
- UTP's own DPAPI-encrypted QwenCloud dashboard credential after the user explicitly saves it.

UTP does not discover credentials in Claude, OpenCode, Qwen, or browser-owned storage. Its OpenCode key is explicitly supplied through UTP or its dedicated environment variable. Provider CLIs manage their own sign-in. The Antigravity adapter no longer reads process CSRF values or local language-server ports.

`UsageFileMonitor.cs` watches UTP usage caches and the configured Claude Desktop usage-history file. Watcher callbacks report file changes; the UI reads normalized quota data without sending file contents elsewhere.

## Network behavior

- ChatGPT/Codex usage is requested from the local Codex app-server process. That provider process may communicate with OpenAI under your existing sign-in.
- Antigravity usage is requested through its separately installed CLI, which may communicate with its provider under the user's sign-in. UTP has no direct Antigravity cloud, OAuth, or loopback fallback.
- When explicitly enabled, OpenCode Go usage is requested directly from `https://opencode.ai/zen/go/v1/usage` with the supplied Bearer API key. This is a usage query, not a model request. No UTP-operated proxy is involved.
- When explicitly enabled, Qwen Token Plan usage is requested from `https://home.qwencloud.com/tool/user/info.json` and `https://cs-data.qwencloud.com/data/api.json` with the user-supplied dashboard session. No UTP-operated proxy is involved.
- UTP does not send usage data or credentials to a UTP-operated server.

Claude normally uses statusline data or its Desktop cache. The optional, explicitly selected isolated CLI usage source asks for control metadata without a user prompt or model request; unavailable account context remains unavailable.

## Uninstalling data

Startup, desktop, and Start-menu shortcuts can be removed independently. UTP does not automatically remove `%APPDATA%\UsageTrayPill`; delete that directory manually if you also want to remove cached settings and notes.

The optional Claude CLI source stores only normalized quota windows and status in `claude-control-usage.json`. Its control request disables transcript-behavior scanning and sends no user message. Provider CLIs manage their own sign-in; UTP does not copy their credentials.
