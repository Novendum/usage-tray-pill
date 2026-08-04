# Threat Model

This document describes the security boundaries of Usage Tray Pill (UTP). It is a release control, not a claim that provider interfaces are stable or risk-free.

## Assets

- User-supplied OpenCode Go and Qwen dashboard sessions.
- Cached usage percentages and reset timestamps.
- Claude statusline and Desktop usage data.
- The integrity of shortcuts, startup entries, the Claude statusline command, and UTP-owned helper processes.

## Trust boundaries

### Local Windows user

UTP runs with the current user's permissions. Windows DPAPI protects optional dashboard credentials at rest from other Windows users, but not from malware or another process already running as the same user.

### Provider applications

ChatGPT/Codex, Claude, and Antigravity are separate local applications. Their local process metadata, files, statusline payloads, and app-server responses are untrusted inputs. UTP validates expected paths, commands, ports, fields, sizes, and timeouts before using them.

### Provider dashboards

OpenCode Go and Qwen are disabled until the user explicitly supplies the minimum dashboard session data. Requests use fixed HTTPS destinations, disable redirects, enforce timeouts and streaming response-size limits, and do not use a UTP-operated proxy.

The OpenCode Go adapter reads quota data from an undocumented hosted dashboard. Interface changes can temporarily break collection; the adapter fails closed or retains only a bounded last-known result.

The Qwen adapter sends the user-supplied Cookie request-header value only to the two fixed QwenCloud dashboard hosts required by the adapter. It polls once every two minutes and blocks overlapping refresh processes.

### Local loopback

Antigravity uses a self-signed loopback HTTPS service. UTP accepts that certificate only for a fixed `127.0.0.1` URL after matching the Antigravity language-server executable, required command arguments, owning process, loopback listener, and temporary CSRF value. The CSRF value is never persisted.

## Primary threats and controls

| Threat | Control |
| --- | --- |
| Credential committed or logged | Credential files and logs are ignored; tests and Gitleaks scan the repository; exceptions contain normalized error messages rather than provider responses. |
| Cookie sent to an unexpected host | Fixed HTTPS host allowlists, disabled redirects, fixed endpoints, and secure cookies. |
| Oversized provider response or statusline payload | Streaming byte or character limits plus bounded timeouts. |
| Unrelated process terminated | Exact helper script-path and command-line matching before process-tree shutdown. |
| Unrelated shortcut or Claude statusline overwritten | Ownership comparison and explicit `-Force` requirement. |
| Stale usage shown as current | Last-success timestamps, bounded stale windows, and authentication failures that clear current values. |
| Malformed local state crashes the tray | Defensive parsing, unavailable states, atomic writes, mutexes, and exception-safe cleanup. |
| Provider UI or API changes | Experimental adapters are opt-in and fail closed or display `--`. |

## Accepted limitations

- A process running as the same Windows user can access UTP's memory and can invoke DPAPI under that user context.
- Provider applications and undocumented dashboard interfaces can change without notice.
- Runtime-loaded provider icons and provider names remain subject to provider trademark policies.
- The Antigravity loopback certificate is not chain-validated; security relies on the validated local process and process-owned listener.

## Review requirements

New network destinations, credential sources, process termination paths, bundled third-party assets, or persistence mechanisms require:

1. A documented trust-boundary update.
2. Regression tests for success, malformed input, timeout, and unavailable states.
3. Privacy and security policy updates.
4. A complete history and worktree secret scan.
