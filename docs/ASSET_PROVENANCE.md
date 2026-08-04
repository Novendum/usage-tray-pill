# Asset Provenance

This document is a release control for every visual asset distributed with Usage Tray Pill.

## UTP application identity

The following files are custom UTP artwork and are not provider logos:

- `assets/utp-logo.svg`
- `assets/tray-icon-light.svg`
- `assets/tray-icon-light.png`
- `assets/tray-icon-light.ico`
- `assets/tray-icon-dark.svg`
- `assets/tray-icon-dark.png`
- `assets/tray-icon-dark.ico`

The SVG files are the deterministic vector sources for the UTP logo and its light and dark Windows icon variants. The runtime PNG and ICO exports are derived from those vectors. The mark combines a pill silhouette, a subtle U shape, and three descending usage bars; it does not contain provider artwork.

High-resolution `*-source.png` working files stay local and are ignored. They contain generative provenance metadata and are not needed to build or run UTP. The deterministic SVG sources and stripped runtime PNG and ICO exports are part of the release package.

## Demo media

`docs/media/usage-tray-pill-demo.mp4` is a locally rendered Remotion product demo. It reconstructs the UTP pill as animated interface components over a sanitized Windows taskbar reference derived from the maintainer's supplied screenshots. The provider indicators are cropped from those contextual pill examples and remain confined to the product demonstration. The render contains no live provider responses, account details, credentials, cookies, local paths, or personal identifiers.

`docs/media/usage-tray-pill-demo-poster.png` is a frame exported directly from that rendered demo for the README preview.

`docs/media/usage-tray-pill-use-case.png` is a locally created image-editing composite based on a maintainer-supplied Windows use-case composition and the sanitized Codex pill screenshot. It shows Codex above a complete Windows 11 taskbar, with the taskbar language indicator set to `EN`. The composite contains no live provider response, account details, credentials, cookies, local paths, or personal identifiers.

- Demo video SHA-256: `600CBDAA211D3418C0114B11754DB863E9035DD9DBF1AF0D62800F52C72C4368`
- Poster SHA-256: `F3CBEA7AD0E1A958482EC2968A2B200594623AE950031611F9D30E6F98A30346`
- Use-case image SHA-256: `89FF4A60B643C22560C9D15D919C3456E0E2AB6D3149850BCE08AEADDD7B8843`
- Rendered and added to the release candidate: 2026-08-03
- Provider marks appear only in the rendered product context and are not used as UTP branding.

## Provider indicators

The provider indicators are used only inside the usage pill to identify the active provider. They are never used as UTP's application icon or project identity.

ChatGPT, Claude, Antigravity, and OpenCode indicators are loaded at runtime from their locally installed desktop applications. Claude's installed monochrome tray template is tinted with UTP's orange provider accent at runtime so it remains recognizable on the white pill. When another installed icon cannot be found, UTP renders its own neutral letter-in-circle fallback.

`assets/qwen-logo.png` is the official 512x512 Qwen Code application icon from the Apache-2.0-licensed `QwenLM/qwen-code` repository. It is used without visual modification and only as the small Qwen provider indicator.

- Official source: <https://github.com/QwenLM/qwen-code/blob/ebf8f7510d6b727a515f339d29ecfe1ab10b5c16/packages/desktop/apps/electron/resources/brands/qwen-code/icon.png>
- Source commit: `ebf8f7510d6b727a515f339d29ecfe1ab10b5c16`
- Retrieved: 2026-07-26
- SHA-256: `02DAC7AE657DDD32793B55CB63C00497807D1B6CF55343CEA2B97120D048839A`
- License: Apache-2.0; bundled at `THIRD_PARTY_LICENSES/QWEN_CODE_APACHE-2.0.txt`
- Trademark use: provider identification only; no endorsement or project branding

## Current external guidance

- OpenAI design guidelines: <https://openai.com/brand/>
- Anthropic newsroom and press kit entry point: <https://www.anthropic.com/news>

OpenAI requires marks to relate directly to its services, remain unmodified, avoid implying endorsement, and remain less prominent than the project's own identity. UTP does not copy or redistribute provider artwork; an icon already installed on the user's computer is used only as a small provider indicator.

Guidance last reviewed: 2026-07-26.
