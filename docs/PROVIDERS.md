# Provider setup and compatibility

[Back to the README](../README.md)

Choose only the providers you use. CLI sign-in is managed by the provider; do not share credentials in issues or chat.

### ChatGPT/Codex

UTP starts the locally installed `codex app-server --stdio` command and requests `account/rateLimits/read`. This local interface is experimental and may change between Codex releases.

The background collector keeps this connection open and normally refreshes every 60 seconds. Select the account limit bucket in Preferences; UTP retains fractional percentages and displays a positive remainder below one percent as `<1%` rather than rounding it to zero.

### Claude

The supported source is the Claude Code statusline JSON. Install the UTP statusline integration with:

```powershell
.\Install-ClaudeStatusLine.ps1
```

Claude documents 5-hour and 7-day usage fields in its statusline. UTP may also read Claude Desktop's local usage history as a fallback.

Preferences also offers **Use Claude CLI quotas (experimental)**. This remains off by default. It uses an isolated, zero-user-message `get_usage` control request with transcript-behavior scanning disabled. Sign in to Claude Code with your subscription first. The selected source uses its own cache and does not silently fall back. Local validation on 2026-10-02 confirmed quota reads with Claude Code 2.1.286 after sign-in, with no model activity; the upstream API remains experimental.

The CLI quota source starts its own isolated helper and does not require Claude Desktop to remain open. An unverifiable quota response is retried after 30 seconds with exponential backoff capped at 15 minutes. Authentication/setup failures and unexpected model or transcript activity remain paused. Invalid responses never become displayed percentages.

### Antigravity

`ExternalUsageAdapters.ps1` invokes an installed Antigravity CLI with `-p /usage --output-format json`. Its strict parser follows an observed output contract, not a Google-published JSON schema. Missing CLI installation produces `setup_required`; unsupported responses remain unavailable. Local validation on 2026-10-02 confirmed the four Gemini/third-party quota windows with signed-in CLI 1.2.14 and zero model turns. The pill shows the restrictive window per family; Details retains all windows. UTP does not install dependencies automatically, inspect language-server CSRF values, or use the former loopback quota service.

### OpenCode Go

OpenCode Go is disabled by default. Open the tray menu and choose **Set up OpenCode Go**, then supply your Go API key. Treat this as a secret: the same key can authorize model usage.

UTP stores the supplied key with current-user Windows DPAPI in its version-2 credential format. It never discovers keys in OpenCode's `auth.json` or browser storage. Every refresh is a direct authenticated GET request to the [official usage endpoint](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts):

```text
https://opencode.ai/zen/go/v1/usage
```

The API supplies 5-hour, weekly, and monthly percentages, statuses, and reset times. UTP normally refreshes every 60 seconds. Temporary errors may retain a clearly cached result for at most six hours. Rejected keys and missing subscriptions pause automatic requests and clear displayed values. The previous version-1 cookie file is preserved without decrypting or using it and requires a new API key; **Disable** preserves saved credentials and cache.

For managed setups, `OPENCODE_GO_API_KEY` takes precedence over UTP's saved key. Legacy workspace/cookie environment variables are no longer used.

### Qwen Token Plan

Qwen is disabled by default. Open the tray menu and choose **Set up Qwen Token Plan**. In the QwenCloud dashboard, open DevTools, refresh the subscription page, select the `tool/user/info.json` request, and copy only the value of **Request Headers > Cookie** into UTP's local setup dialog. Never paste this value into a bug report or chat.

UTP encrypts the session header with Windows DPAPI for the current Windows user. It does not read Qwen CLI settings, inference keys, or browser cookie databases. This adapter uses the dashboard session, not the inference API key. The separate QwenCloud CLI has not been validated as a replacement for this Personal-plan contract.

When enabled, refreshes request only `home.qwencloud.com/tool/user/info.json` and the Token Plan usage gateway on `cs-data.qwencloud.com`, normally every two minutes without overlap. These dashboard interfaces can change; the current adapter recognizes 5-hour and weekly windows, not every newer plan variant. Temporary errors may retain cached values for at most six hours; expired authentication clears them and pauses requests. The Qwen checkbox in Preferences disables collection without deleting the encrypted session or cache.

For managed setups, `QWEN_TOKEN_PLAN_COOKIE` may supply the complete Cookie request-header value. It takes precedence over UTP's encrypted local credential.

### Cursor

Cursor is not implemented in UTP. No Cursor account credentials or private application caches are read.
