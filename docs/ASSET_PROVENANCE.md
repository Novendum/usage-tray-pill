# Asset Provenance

This document is a release control for every visual asset distributed with Usage Tray Pill.

The users' ZIP contains runtime icons and their licenses. Demo media and launch artwork described below remain in the source repository and are not included in that ZIP.

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

## October 2026 launch media

- `docs/media/utp-launch-cover.png`: new brand artwork made with the built-in image generation tool on 2026-10-02. Stylized product artwork based on the existing cover, the synthetic light/dark rendering board and a maintainer-supplied close-up of the light pill. It shows a sharp light OpenAI pill and a softly blurred dark Claude pill with illustrative values. This is generated artwork, not a pixel-exact application screenshot. Provider marks appear only within the depicted product interface; no account identifiers or credentials were supplied. The exact prompt is in `docs/media/launch-cover-prompt.txt`. The original image retains its generation provenance metadata.
- `docs/media/utp-pill-themes.png`: an editorial comparison board drawn with the production UTP renderer by `Test-UtpInteractions.ps1 -OutputDirectory <temporary-directory>`, at 200% logical DPI. The labels and both themes are real app rendering; all quota values are synthetic.
- `docs/media/utp-overview.png`: the real WinForms overview rendered offscreen by the same isolated fixture. It shows invented values, an unconfigured Antigravity source and paused Qwen, not an account capture. Provider marks remain small indicators in product context.

- `docs/media/utp-two-providers.png` (2026-10-10, rc.6): release artwork for the two-provider pill. The large light pill (300%) and the dark taskbar pill (125%) are drawn by the production renderer (`New-TaskbarBadgeSegmentBitmap`); quota values are synthetic. The bloom background, headline, abstract taskbar tiles, clock and feature line are composed with GDI+ around those renders and are illustrative; no third-party app icons are depicted beyond the provider indicators inside the pills. No screenshot, account cache or provider request was used.

- `docs/media/utp-promo.mp4` (2026-10-10): a 12-second promo film (1920x1080, 30 fps, H.264 with AAC stereo, -14 LUFS integrated, -1 dBFS peak), rendered locally with HyperFrames from an HTML/GSAP composition. It is an animated product illustration, not a screen recording: the pill is reconstructed with the app's Segoe UI Bold styling, the provider indicators are the same 192 px icons UTP renders, and all quota values are synthetic. It carries no version number so it stays valid across releases. Sound effects are recordings from Pixabay used under the [Pixabay Content License](https://pixabay.com/service/license-summary/) (bundled with HyperFrames media-use); the music bed was generated locally with Meta's MusicGen (`facebook/musicgen-small`). No account cache, provider request, voice-over or stock footage was used.

The README opens with the promo film (played from a GitHub video attachment of `utp-promo.mp4`) and labels it as an animated illustration with illustrative values; the generated cover remains launch artwork for `docs/LAUNCH.md`. Older demo media remains historical and is labeled accordingly; it is not evidence of the current appearance.

- `utp-launch-cover.png` SHA-256: `858184d120325525eb1e2eb044a84759eb05d7eef9d3fcd52d24b99887cd7f17`
- `utp-pill-themes.png` SHA-256: `57d790f55bee07545a13f15ba15a9a9c468def624a23f6e5bed2037ecc29a35c`
- `utp-overview.png` SHA-256: `9a1fb2086b2e6f005733abf8d72fd1c4678083bbd08aff7ca82498f34553f023`
- `utp-two-providers.png` SHA-256: `2ac39c971b4724baa4cc45f9e24b6b903c8d2cee79cd794d96fc5296cce7b658`
- `utp-promo.mp4` SHA-256: `fd0593d192461cbc643de1026866b53794129afab3812a27ce65709947e305c7`
