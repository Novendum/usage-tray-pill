# Security Policy

## Supported versions

During the release-candidate phase, only the latest commit on the default branch is supported.

## Reporting a vulnerability

Do not open a public issue for suspected credential exposure or code execution vulnerabilities. Use a [private GitHub security advisory](https://github.com/Novendum/usage-tray-pill/security/advisories/new). Private vulnerability reporting is enabled for this public repository.

Include reproduction steps and affected UTP files, but never include tokens, `.credentials.json`, `%APPDATA%\UsageTrayPill`, account identifiers, or provider responses containing personal data.

## Security boundaries

- Provider credentials must never be committed, logged, copied, returned from tests, or included in exceptions.
- UTP must not discover, refresh, or modify credentials in provider-owned files. Provider CLIs retain responsibility for their own sign-in.
- The optional OpenCode Go adapter may transmit only an explicitly supplied Go API key to `https://opencode.ai/zen/go/v1/usage`. Its version-2 UTP credential file must use current-user Windows DPAPI and never contain a plaintext key. `OPENCODE_GO_API_KEY` is an explicit alternative; legacy cookie records must not be decrypted or used.
- UTP must not automatically inspect OpenCode `auth.json`, other provider key stores, browser histories, or browser cookie databases. A Go key is not a read-only credential; the usage collector must never send inference requests.
- The optional Qwen adapter may transmit the user-supplied dashboard Cookie header only to `home.qwencloud.com` and `cs-data.qwencloud.com`. Its UTP-owned credential file must use current-user Windows DPAPI and must never contain the plaintext header.
- UTP must not automatically inspect Qwen CLI settings, Qwen API keys, browser histories, or browser cookie databases.
- Disabling a provider must stop collection without deleting its credentials or cache. Auth and entitlement failures must pause automatic retries; explicit reconnection or refresh controls may retry.
- External CLI output is untrusted. Adapters must bound execution and output, reject unsupported contracts, and never infer subscription quota from token counts or model cost. Antigravity language-server/CSRF scraping is not supported.
- The optional Claude control diagnostic must send no user prompt or model request and must reject unexpected model activity or unsupported authentication context.
- HTTP requests use fixed destinations, disabled redirects, response-size limits, and a total request deadline; per-read timeouts alone are insufficient.
- Current-user DPAPI protects stored credentials at rest, but it does not protect them from other processes already running as the same Windows user.
- Experimental provider integrations must be disabled by default and clearly identified in the UI and documentation.
- UTP may stop only helper processes it started and identified by exact executable path and command line.
- New network destinations require documentation, tests, and maintainer review.
