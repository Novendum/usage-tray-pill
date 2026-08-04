# Security Policy

## Supported versions

Until the first public release, only the latest commit on the default branch is supported.

## Reporting a vulnerability

Do not open a public issue for suspected credential exposure or code execution vulnerabilities. Use a [private GitHub security advisory](https://github.com/Novendum/usage-tray-pill/security/advisories/new) once the repository accepts them. While the project remains private, invited collaborators should use an agreed private channel with the repository owner.

Include reproduction steps and affected UTP files, but never include tokens, `.credentials.json`, `%APPDATA%\UsageTrayPill`, account identifiers, or provider responses containing personal data.

## Security boundaries

- Provider credentials must never be committed, logged, copied, returned from tests, or included in exceptions.
- UTP must not read, transmit, refresh, or modify provider credential files or access tokens.
- The optional OpenCode Go adapter may transmit only the user-supplied dashboard `auth` cookie to `https://opencode.ai/workspace/<workspace-id>/go`. Its UTP-owned credential file must use Windows DPAPI for the current user and must never contain the plaintext cookie.
- UTP must not automatically inspect OpenCode `auth.json`, API keys, browser histories, or browser cookie databases.
- The optional Qwen adapter may transmit the user-supplied dashboard Cookie header only to `home.qwencloud.com` and `cs-data.qwencloud.com`. Its UTP-owned credential file must use current-user Windows DPAPI and must never contain the plaintext header.
- UTP must not automatically inspect Qwen CLI settings, Qwen API keys, browser histories, or browser cookie databases.
- Current-user DPAPI protects stored credentials at rest, but it does not protect them from other processes already running as the same Windows user.
- Experimental provider integrations must be disabled by default and clearly identified in the UI and documentation.
- UTP may stop only helper processes it started and identified by exact executable path and command line.
- New network destinations require documentation, tests, and maintainer review.
