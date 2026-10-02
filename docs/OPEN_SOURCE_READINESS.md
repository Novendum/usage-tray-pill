# Open-source readiness

Reviewed: 2026-10-02. The repository is already public. This record distinguishes the published baseline from the local October update.

## Published baseline

Public main was `814714061b7f8d23f1f3346db940e195e5778c62` at review time. Both required jobs passed in [GitHub Actions](https://github.com/Novendum/usage-tray-pill/actions/runs/30903908068). Tag `v0.1.0-rc.1` exists, but no GitHub Release was listed. These checks predate the October update.

The earlier clean-root publication is complete. Preserve its history and the later README/demo fixes. The [August readiness record](https://github.com/Novendum/usage-tray-pill/blob/814714061b7f8d23f1f3346db940e195e5778c62/docs/OPEN_SOURCE_READINESS.md) is historical evidence, not the current checklist.

## October update

- Persistent collection, Codex connection reuse, file-change notifications and bounded retries.
- OpenCode Go JSON usage API with an explicitly supplied key, replacing dashboard cookies.
- Antigravity CLI usage; optional, default-off experimental Claude CLI quotas.
- Automatic light/dark appearance, native text, smooth alpha edges and queued provider switching.
- Explicit Qwen enable/disable control retaining the saved connection; no hover popup.
- Updated README, setup guide, fixture-rendered product images and generated launch artwork.

MIT licensing, contributor guidance, reporting templates, privacy/security policies, third-party notices and the threat model remain part of the distribution.

## Verification boundaries

Development checks passed in Windows PowerShell 5.1, including the aggregate suite, pill rendering at 100/125/150/175/200% scale, interaction, collector lifecycle, isolated provider fixtures and relocated selftests. Final package verification is recorded separately below when completed.

Local signed-in reads were observed with Codex, Claude Code 2.1.286, Antigravity CLI 1.2.14 and OpenCode Go. The Claude control check sent no user prompt and showed no model activity; Antigravity returned four windows with zero model turns. No personal quota values or raw provider responses appear in the new media.

## Remaining work

- Full manual OpenCode failure/setup/DPAPI matrix and Qwen plan/session matrix.
- Qwen was disabled during the current live check; no new compatibility claim is made for it.
- Fresh Windows user and multiple physical monitor configurations.
- GitHub checks on the actual proposed update. Local tests do not prove publication or all-account compatibility.
- Final release archive, version/tag and the X announcement.

Follow [Release checklist](RELEASE_CHECKLIST.md) and [Repository settings](REPOSITORY_SETTINGS.md). Never rewrite public history to match a local checkout.

## Local package verification, 2026-10-02

The October candidate was assembled from tracked and non-ignored new files without changing the Git index. Its extracted copy passed the complete Windows PowerShell 5.1 suite from a directory containing spaces. The checksum-verified Gitleaks 8.30.1 scanner found no leaks in the package contents. Runtime-data filenames, relative links in the updated docs, media hashes and targeted private-data markers were also checked.

The generated cover, actual light/dark rendering and overview image were visually inspected. GitHub's Markdown API accepted the README. The local HTML browser preview was blocked by the browser's file-URL policy, so final GitHub-page layout verification remains on the publication checklist.

After recording these results, only publication documentation and media changed; the final package's script/native-code hashes were compared with the tested copy. Package contents were rescanned and matched against a SHA-256 manifest. This is local candidate evidence, not a claim that GitHub contains the update. At that local preparation stage, no commit, push, tag, release, repository-setting change or X post had been performed.
