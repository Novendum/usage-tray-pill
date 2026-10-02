# October update: launch kit

Prepared for @Debuggerdam. Draft only: post after the GitHub update is merged and the public download has been checked.

## X post

I rebuilt Usage Tray Pill, the tiny Windows taskbar tool I use to check my AI limits.

Sharper text. Light and dark themes. Smoother switching. Better quota fetching.

Open source, as always. Try it and tell me what breaks:
https://github.com/Novendum/usage-tray-pill

Attach `media/utp-launch-cover.png` first and `media/utp-pill-themes.png` second. The first is generated brand artwork; the second is real UTP rendering with fictitious values. Do not use the owner's account screenshot as launch media.

Suggested image descriptions:

- Cover: "Usage Tray Pill. Small pill. Clear limits. AI usage in your Windows taskbar. A sharp light OpenAI usage pill floats in front of a softly blurred dark Claude pill, on a pale background. All values are illustrative."
- Product: "Actual Usage Tray Pill rendering in light and dark themes, with example Codex weekly and Claude five-hour and weekly allowances. Values are illustrative."

## Pull request draft

Title: **Modernize quota collection and refresh the Windows pill experience**

UTP's published adapters and taskbar presentation lag behind current provider interfaces. This update adds persistent background collection with explicit freshness and retry handling, moves OpenCode Go to its usage API, uses the Antigravity CLI and offers an opt-in experimental Claude CLI quota source. It improves pill rendering, automatic light/dark appearance and interactions.

The README now starts with a short install path, current requirements and sanitized product images. Preserve the public history and repaired demo link. OpenCode users must supply a Go key when migrating from cookies; Qwen stays off by default.

Before submitting, add final package verification and GitHub checks. Retain the manual compatibility limits from the release checklist.

## Release-note draft

This update makes the pill easier to read and improves allowance collection.

- Automatic light/dark appearance, bold native text, smooth capsule edges and correctly sized icons.
- Queued provider switching and no hover instructions.
- Persistent collector/Codex connection, cache updates, bounded retries and clearer missing-data states.
- OpenCode Go usage API, Antigravity CLI quotas and optional experimental Claude CLI quotas.
- Qwen can be paused and enabled again without deleting the saved connection.

**Upgrade:** exit UTP, replace the complete application folder and start again. Supply a Go API key when upgrading the cookie integration. Antigravity requires its separately installed CLI. Claude CLI quotas remain experimental and off by default.

**Known limits:** provider interfaces can change. Qwen's plan/session variants and the full manual OpenCode failure matrix are not certified. Polling is periodic, not an instant provider push feed. See the readiness record.

Choose the version after reviewing the actual GitHub diff. Preparing this file does not publish a release or X post.
