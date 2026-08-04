# Privacy

Usage Tray Pill is a local Windows utility. It has no UTP telemetry service, analytics service, advertising service, or UTP account system.

## Data stored by UTP

UTP stores settings, manual notes, cached usage percentages, reset timestamps, and local helper logs under `%APPDATA%\UsageTrayPill`. Normalized Antigravity quota data is stored in `antigravity-usage.json`; it contains no account identity or CSRF value. Normalized OpenCode Go and Qwen quota data is stored in `opencode-go-usage.json` and `qwen-token-plan-usage.json`.

When OpenCode Go is explicitly configured, `opencode-go-credentials.json` contains the workspace ID and a dashboard `auth` cookie encrypted with Windows DPAPI for the current Windows user. The plaintext cookie is not written to disk by UTP.

When Qwen Token Plan is explicitly configured, `qwen-token-plan-credentials.json` contains the user-supplied QwenCloud Cookie request-header value encrypted with Windows DPAPI for the current Windows user. The plaintext header is not written to disk by UTP.

Do not include this directory in bug reports. Manual notes may contain information you entered yourself.

## Local data read by UTP

Depending on enabled features, UTP may read:

- the Windows process list to detect ChatGPT, Codex, Claude, Antigravity, fullscreen applications, and UTP-owned helpers;
- local ChatGPT/Codex installation paths to find an application icon;
- Claude Code statusline JSON sent directly to the configured UTP script;
- Claude Desktop's local `plan-usage-history.json` cache.
- the executable path, command line, and loopback listening ports of Antigravity's language server so UTP can authenticate a local quota request.
- UTP's own DPAPI-encrypted OpenCode Go dashboard credential after the user explicitly saves it.
- UTP's own DPAPI-encrypted QwenCloud dashboard credential after the user explicitly saves it.

UTP does not read Claude, OpenCode, or Qwen credential files, provider API keys, browser cookie databases, or provider access tokens. Antigravity's temporary CSRF value is read from its running process, used only for the local loopback request, and never persisted or logged.

## Network behavior

- ChatGPT/Codex usage is requested from the local Codex app-server process. That provider process may communicate with OpenAI under your existing sign-in.
- Antigravity usage is requested only from Antigravity's local HTTPS language server on `127.0.0.1`. UTP has no Antigravity cloud or OAuth fallback.
- When explicitly enabled, OpenCode Go usage is requested directly from `https://opencode.ai/workspace/<workspace-id>/go` with the user-supplied dashboard cookie. No UTP-operated proxy is involved.
- When explicitly enabled, Qwen Token Plan usage is requested from `https://home.qwencloud.com/tool/user/info.json` and `https://cs-data.qwencloud.com/data/api.json` with the user-supplied dashboard session. No UTP-operated proxy is involved.
- UTP does not send usage data or credentials to a UTP-operated server.

## Uninstalling data

Startup, desktop, and Start-menu shortcuts can be removed independently. UTP does not automatically remove `%APPDATA%\UsageTrayPill`; delete that directory manually if you also want to remove cached settings and notes.
