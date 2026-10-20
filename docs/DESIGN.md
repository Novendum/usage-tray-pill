# UTP desktop design

## Direction
Operate mode. A compact studio meter: an obsidian taskbar capsule paired with an uncluttered, warm-white usage console. Actual quota windows form readable horizontal meter tracks. No invented metrics, decorative graphs, gradients, or animated background effects.

Creative direction was delegated by the owner. Native Windows typography, focus, resizing, screen-reader text, and reduced-motion preferences take precedence over web design conventions. Keep the UTP magenta identity and approved provider artwork.

## System
- Capsule follows the Windows taskbar theme (`SystemUsesLightTheme`): light #FAFBFD with dark text, or ink #202126 with light text. Quota colors, border, and provider artwork adapt together. Preserve alpha-blended edges in both themes.
- Position keeps 12 additional logical pixels of space from the notification-area arrow compared with the original placement; the offset scales with DPI.
- Workspace: paper #F5F4F1, white content, ink #24262C, muted #636875, magenta #D02279.
- Segoe UI / Segoe UI Semibold: native platform voice. Numerical values are prominent, labels compact, unavailable states explicit.
- Pill labels and values use bold Segoe UI at the same readable size. Do not downgrade period labels to small regular text; maintain strong contrast in both taskbar themes.
- Two-provider pill: each side is logo + bold label/value pairs at the same size as the single pill; period labels shorten to `5h`, `wk`, `mo`. Sides are separated by a quiet one-device-pixel divider in the border tone, never by color blocks. Values reserve two digits so routine changes do not resize the capsule.
- Rasterize pill text with native GDI at final pixel size on its known opaque background, then preserve the capsule alpha mask during composition. Generate icons at the final DPI size; never enlarge a 22-pixel intermediate image.
- Provider rows are flat, with dividers and generous vertical rhythm. Quota tracks represent remaining percentage and never show a fake value for unavailable data.
- Primary actions are magenta; secondary actions are quiet and clearly keyboard-focusable.
- One transition system: the existing queued 220 ms provider change. Hover gives information; it never changes provider.
- App icon: a teal tile with a white U and three amber usage bars, drawn per size by `scripts/Build-AppIcon.ps1`. Sizes up to 32 px snap the bars to whole pixels so they stay crisp. Magenta remains the interface accent.
- Overview dark mode follows the Windows app mode: paper #191A1E, surfaces #232429, text #EAECF2, muted #A0A5B2, magenta unchanged, with a native dark title bar and dark scroll bars.
- Quick view: a 372-logical-pixel flyout above the pill in the taskbar theme. Each window gets one row with a 4 px remaining-allowance meter (magenta, red under 20%, neutral when cached), its reset text, and two footer actions; a quiet **⋯** in the header opens the full menu. It opens and closes without animation.
- Attention dot: a small red dot (#D63031 light, #FF665C dark) with a surface ring on the provider logo's top-right corner, only when the user must act. Low allowance never uses it; that stays in the quota colours.

## Verification
Render the native overview and capsule with deterministic synthetic data; check minimum and expanded window sizes, missing data, expired sessions, multi-window providers, and fractional DPI. Retain the full behavior tests. Restart only the exact owned UTP runtime after local validation.
