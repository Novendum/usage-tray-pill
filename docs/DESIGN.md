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
- Rasterize pill text with native GDI at final pixel size on its known opaque background, then preserve the capsule alpha mask during composition. Generate icons at the final DPI size; never enlarge a 22-pixel intermediate image.
- Provider rows are flat, with dividers and generous vertical rhythm. Quota tracks represent remaining percentage and never show a fake value for unavailable data.
- Primary actions are magenta; secondary actions are quiet and clearly keyboard-focusable.
- One transition system: the existing queued 220 ms provider change. Hover gives information; it never changes provider.

## Verification
Render the native overview and capsule with deterministic synthetic data; check minimum and expanded window sizes, missing data, expired sessions, multi-window providers, and fractional DPI. Retain the full behavior tests. Restart only the exact owned UTP runtime after local validation.
