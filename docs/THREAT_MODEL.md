# Threat Model

This document describes the security boundaries of Usage Tray Pill (UTP). It is a release control, not a claim that provider interfaces are stable or risk-free.

## Assets

- The user-supplied OpenCode Go API key and Qwen dashboard session.
- Cached usage percentages and reset timestamps.
- Claude statusline and Desktop usage data.
- The integrity of shortcuts, startup entries, the Claude statusline command, and UTP-owned helper processes.

## Trust boundaries

### Local Windows user

UTP runs with the current user's permissions. Windows DPAPI protects UTP's optional credentials at rest from other Windows users, but not from malware or another process already running as the same user. An OpenCode Go API key can authorize model use; its use by this collector is restricted to the quota GET endpoint.

### Provider applications

ChatGPT/Codex, Claude, and Antigravity are separate local applications. Their executable paths, command output, usage files, statusline payloads, and app-server responses are untrusted inputs. UTP validates commands, fields, sizes, and timeouts before using them. Codex's persistent stdio connection is owned by the hidden collector; external provider CLIs manage their own sign-in, without UTP reading their credential stores.

### Provider usage services

OpenCode Go and Qwen are opt-in. OpenCode takes an explicitly supplied API key; Qwen takes a dashboard session. Requests use fixed HTTPS destinations, disable redirects, enforce streaming response-size limits and a 15-second total request deadline, and do not use a UTP-operated proxy.

OpenCode Go uses the official `https://opencode.ai/zen/go/v1/usage` GET endpoint. It preserves server percentages and reset timestamps rather than estimating quota from local spend. Legacy version-1 cookie credentials remain untouched and unused; users must explicitly save a replacement key. The dedicated environment variable overrides the saved key. Rejected keys and missing Go entitlement are separate unavailable states.

The Qwen adapter sends the supplied Cookie header only to the two fixed QwenCloud dashboard hosts. When enabled, it normally polls every two minutes without overlap. Disabling it preserves the encrypted credential and cache and stops collection. Its dashboard contract may not cover newer plan variants.

### External command contracts

Antigravity uses a separately installed CLI's usage command. The JSON schema is an observed integration contract, not an official provider schema; unsupported output must remain unavailable. The former loopback certificate exception and CSRF discovery are removed. CLI 1.2.14 was validated locally on 2026-10-02; subsequent versions still require contract validation.

Claude statusline and Desktop cache remain its ordinary sources. The optional isolated CLI control diagnostic sends no user prompt, asks for usage metadata, and rejects unexpected model activity or unsupported auth context. After explicit sign-in, the 2.1.286 probe established account quota without model activity. The interface remains experimental, off by default, and explicitly selectable in Preferences. External commands have bounded output and a 30-second execution limit, with a separate version check; they must not silently fall back to model inference.

### Collector and UI

One hidden collector isolates provider work in separate persistent runspaces. Authentication and entitlement failures pause automatic retries. Other failures back off from 30 to 900 seconds or honor bounded provider retry guidance. The UI watches normalized cache changes, and a 45-second manual-refresh watchdog may stop only its owned collector. These controls keep provider failures off the UI thread; they do not guarantee immediate provider reporting.

## Primary threats and controls

| Threat | Control |
| --- | --- |
| Credential committed or logged | Credential files and logs are ignored; tests and Gitleaks scan the repository; exceptions contain normalized error messages rather than provider responses. |
| Key or cookie sent to an unexpected host | Fixed HTTPS destinations, disabled redirects, and no automatic credential discovery. |
| Oversized provider response or statusline payload | Streaming byte or character limits plus bounded timeouts. |
| Unrelated process terminated | Exact helper script-path and command-line matching before process-tree shutdown. |
| Unrelated shortcut or Claude statusline overwritten | Ownership comparison and explicit `-Force` requirement. |
| Stale usage shown as current | Last-success timestamps, bounded stale windows, and authentication failures that clear current values. |
| Malformed local state crashes the tray | Defensive parsing, unavailable states, atomic writes, mutexes, and exception-safe cleanup. |
| Provider UI or API changes | Experimental adapters are opt-in and fail closed or display `--`. |
| Repeated unauthorized requests | Automatic pause on auth/setup/entitlement failures, bounded retry delays otherwise. |
| Diagnostic starts inference | No user prompt, explicit usage-control request, unexpected model-activity rejection, and command timeout. |
| CLI error mistaken for no usage | Strict response validation; unsupported or missing context remains unavailable. |

## Accepted limitations

- A process running as the same Windows user can access UTP's memory and can invoke DPAPI under that user context.
- Provider applications and undocumented dashboard interfaces can change without notice.
- Runtime-loaded provider icons and provider names remain subject to provider trademark policies.
- CLI execution and sign-in behavior depend on the installed provider version. Offline fixtures do not establish account compatibility or absence of future provider-side behavior changes.
- Provider accounting delays remain possible even when the collector and file-change notifications are healthy.

## Review requirements

New network destinations, credential sources, process termination paths, bundled third-party assets, or persistence mechanisms require:

1. A documented trust-boundary update.
2. Regression tests for success, malformed input, timeout, and unavailable states.
3. Privacy and security policy updates.
4. A complete history and worktree secret scan.
