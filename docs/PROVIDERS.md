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

The CLI quota source starts its own isolated helper and does not require Claude Desktop to remain open. Successful reads refresh every three minutes. Claude can report account eligibility while returning no quota data; UTP treats this as a temporary fetch failure and waits at least five minutes before retrying, with backoff capped at 15 minutes. Other transient failures start with a 30-second retry.

After a temporary failure, verified values may remain visible for at most ten minutes from the last successful read, marked **cache** on the pill and with their observation time in the overview. Each window also expires at its reset time. Failed attempts never extend this lifetime. Authentication/setup failures and unexpected model or transcript activity clear values and pause collection. Invalid responses never become displayed percentages.

### Antigravity

`ExternalUsageAdapters.ps1` invokes an installed Antigravity CLI with `-p /usage --output-format json`. Its strict parser follows an observed output contract, not a Google-published JSON schema. Missing CLI installation produces `setup_required`; unsupported responses remain unavailable. Local validation on 2026-10-02 confirmed the four Gemini/third-party quota windows with signed-in CLI 1.2.14 and zero model turns. The pill shows the restrictive window per family; Details retains all windows. UTP does not install dependencies automatically, inspect language-server CSRF values, or use the former loopback quota service.

UTP sets `AGY_CLI_DISABLE_AUTO_UPDATE=true` only for its Antigravity CLI version and quota reads. This prevents a background usage check from starting AGY's updater or a transient terminal window. It does not change the user's normal CLI environment or update settings. The exact string value is required by the behavior described in [AGY issue 1046](https://github.com/google-antigravity/antigravity-cli/issues/1046).

### OpenCode Go

OpenCode Go is disabled by default. Open the tray menu and choose **Set up OpenCode Go**, then supply your Go API key. Treat this as a secret: the same key can authorize model usage.

UTP stores the supplied key with current-user Windows DPAPI in its version-2 credential format. It never discovers keys in OpenCode's `auth.json` or browser storage. Every refresh is a direct authenticated GET request to the [official usage endpoint](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts):

```text
https://opencode.ai/zen/go/v1/usage
```

The API supplies 5-hour, weekly, and monthly percentages, statuses, and reset times. UTP normally refreshes every 60 seconds. Temporary errors may retain a clearly cached result for at most six hours. Rejected keys and missing subscriptions pause automatic requests and clear displayed values. The previous version-1 cookie file is preserved without decrypting or using it and requires a new API key; **Disable** preserves saved credentials and cache.

For managed setups, `OPENCODE_GO_API_KEY` takes precedence over UTP's saved key. Legacy workspace/cookie environment variables are no longer used.

Changing the saved key or active environment key invalidates quotas from the previous connection. Pauses and retry deadlines survive collector restarts; use an explicit refresh after resolving a paused source's setup or authentication issue.

### Qwen Token Plan

Qwen is disabled by default. Open the tray menu and choose **Set up Qwen Token Plan**. In the QwenCloud dashboard, open DevTools, refresh the subscription page, select the `tool/user/info.json` request, and copy only the value of **Request Headers > Cookie** into UTP's local setup dialog. Never paste this value into a bug report or chat.

UTP encrypts the session header with Windows DPAPI for the current Windows user. It does not read Qwen CLI settings, inference keys, or browser cookie databases. This adapter uses the dashboard session, not the inference API key. The separate QwenCloud CLI has not been validated as a replacement for this Personal-plan contract.

When enabled, refreshes request only `home.qwencloud.com/tool/user/info.json` and the Token Plan usage gateway on `cs-data.qwencloud.com`, normally every two minutes without overlap. These dashboard interfaces can change; the current adapter recognizes 5-hour and weekly windows, not every newer plan variant. Temporary errors may retain cached values for at most six hours; expired authentication clears them and pauses requests. The Qwen checkbox in Preferences disables collection without deleting the encrypted session or cache.

For managed setups, `QWEN_TOKEN_PLAN_COOKIE` may supply the complete Cookie request-header value. It takes precedence over UTP's encrypted local credential.

Replacing the session invalidates the previous connection's quota cache. Disabling and re-enabling collection preserves the current connection and its retry deadline.

### Cursor

Cursor is not implemented in UTP. No Cursor account credentials or private application caches are read.
