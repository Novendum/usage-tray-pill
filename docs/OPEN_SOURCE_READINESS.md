# Open-Source Readiness

Last reviewed: 2026-08-04.

The reviewed source is prepared for public release-candidate publication. Remaining provider-specific scenarios are tracked as manual compatibility checks and do not contain or require publishing account data.

## Completed locally

- MIT license, changelog, contribution guide, Code of Conduct, security policy, privacy disclosure, architecture notes, issue and pull request templates, and third-party notices exist.
- A repository-specific threat model and safe support guidance document assets, trust boundaries, accepted limitations, and disclosure boundaries.
- Recommended repository description, topics, feature settings, branch protection, and release handling are documented for the private-to-public transition.
- Runtime data, logs, shortcuts, credentials, and local account data are ignored and absent from the tracked repository. The included rendered product demo and derived poster are sanitized media with documented provenance.
- The complete private Git history and current worktree passed Gitleaks 8.30.1 on 2026-07-26; the downloaded release archive was checked against GitHub's published SHA-256 before execution.
- All PowerShell files parse successfully. The aggregate Windows PowerShell 5.1 suite passes, including a runtime selftest from a temporary path containing spaces.
- Fractional-DPI badge layout has regression coverage at 175%, including provider-logo centering and exact inter-item spacing.
- PSScriptAnalyzer 1.25.0 found no high-signal credential, `Invoke-Expression`, global-state, or automatic-variable findings after remediation. Remaining analyzer warnings are style-oriented WinForms/PowerShell naming and host-output guidance, not a clean-lint claim.
- Hidden launch, click-only provider switching, fullscreen logic, dynamic layouts, Claude snapshot handling, and credential-safety guards have automated coverage.
- Installers refuse to overwrite unrelated shortcuts or an existing Claude statusline unless the user explicitly supplies `-Force`.
- Uninstallers refuse to delete unrelated shortcuts and only remove the Claude statusline managed by the current checkout.
- Fable-specific OAuth access and provider credential parsing have been removed; Claude uses only statusline or Desktop history data.
- OpenCode Go is opt-in, uses current-user DPAPI for its UTP-owned dashboard credential, and has parser, credential-isolation, and dynamic-layout coverage.
- Qwen Token Plan is opt-in, uses current-user DPAPI for its UTP-owned dashboard credential, and has parser, credential-isolation, stale-cache, and dynamic-layout coverage.
- OpenCode Go, Qwen, and Antigravity response bodies are rejected while streaming when they exceed their provider-specific size limit rather than only after allocation.
- Claude statusline input is streamed with a one MiB character limit before JSON parsing.
- The Claude statusline installer and uninstaller recognize only the exact current or legacy UTP command and preserve deceptive or unrelated commands that merely contain a UTP path.
- Tray timers, the notification icon, helper processes, window resources, and the single-instance mutex are cleaned up through an exception-safe runtime lifecycle.
- Codex app-server standard error is drained asynchronously so a verbose child process cannot block on a full redirected stream.
- GitHub Actions includes a Gitleaks job with a full-history checkout for every push, pull request, and manual run.
- GitHub Actions dependencies are pinned to reviewed commit SHAs, the Gitleaks CLI is pinned by version and GitHub-published SHA-256, checkout credentials are not persisted, jobs have explicit timeouts, and Dependabot checks action updates weekly.
- ChatGPT, Claude, Antigravity, and OpenCode artwork is loaded from locally installed applications. The official Qwen Code icon is the only separately distributed runtime provider asset; its exact source commit, checksum, Apache-2.0 license, and trademark use are documented. Provider indicators embedded in the rendered demo are documented as contextual product footage derived from the maintainer-supplied examples.
- High-resolution artwork sources with C2PA generator metadata are ignored; release PNG and ICO exports contain no textual, EXIF, C2PA, or trailing metadata.
- The publication history is intentionally reduced to one reviewed parentless root commit. Its reachable objects contain neither removed provider artwork, private predecessor history, nor superseded development media.
- A manual single-agent security pass reviewed network allowlists, redirects, streaming limits, credential handling, DPAPI scope, process ownership, persistence installers, local file writes, native calls, CI permissions, and public-release metadata.
- The then-current worktree and reachable clean-root history passed Gitleaks 8.30.1 again on 2026-07-29.
- The reachable clean-root history and the then-current tracked diff passed the locally retained Gitleaks 8.30.1 binary again on 2026-07-30.
- The full Windows PowerShell 5.1 suite passed again on 2026-07-30 after aligning the 175% DPI assertion with the user-approved one-pixel optical logo lift.
- The active runtime was observed across a complete 125-second refresh window on 2026-07-30. It remained responsive, used at most two simultaneous PowerShell provider helpers, and retained no provider helper afterward.
- On 2026-08-03, the real Desktop, Start-menu, and Startup shortcut uninstall/install cycle passed without `-Force`; all recreated shortcuts used the current checkout, icon, working directory, and hidden window style.
- On 2026-08-03, the then-current 48-file release candidate passed the aggregate Windows PowerShell 5.1 suite and launched successfully from a temporary path containing spaces. The test runtime exposed a visible UTP window, retained no helper process, and the normal checkout was restored afterward.
- On 2026-08-03, the current 50-file staged release candidate passed the aggregate Windows PowerShell 5.1 suite from a fresh index-tree archive extracted to a path containing spaces. The package included the sanitized demo video and poster, and the complete candidate directory passed Gitleaks 8.30.1 with no findings.
- On 2026-08-03, private GitHub `main` passed both required Actions jobs: Windows PowerShell 5.1 and the pinned, checksum-verified Gitleaks 8.30.1 full-history scan.
- On 2026-08-03, a 140-second live poll observation saw one OpenCode helper and one Qwen helper, never more than one per provider, no overlap, no missing main runtime, and no retained helper afterward.
- The tray icon and README now use UTP-owned deterministic SVG artwork with light and dark PNG/ICO exports. The exports contain no detected textual metadata, generator marker, local user path, or account data.
- On 2026-08-03, the final 1920x1080 Remotion product demo and README poster replaced the earlier recording. Their documented hashes match the tracked files, targeted binary privacy-pattern checks found no local path, account, cookie, or key markers, Gitleaks 8.30.1 found no leaks in the current directory, and the 50 tracked files passed the aggregate Windows PowerShell 5.1 suite from a temporary path containing spaces.
- On 2026-08-04, a fresh mirror of the replacement private repository contained only `main` and the release-candidate tag, with no pull-request refs, forks, personal commit addresses, account identifiers, local user paths, credential files, or known secret patterns. The final media set was also inspected for personal visual content and metadata.
- The owner namespace, repository description, topics, public issue target, and private security-advisory target now consistently use `Novendum/usage-tray-pill`.

## Remaining manual compatibility checks

1. Complete the remaining OpenCode Go setup, disable, expired-auth, rate-limit, stale-cache, and current-user DPAPI checks when suitable test sessions are available.
2. Complete the equivalent Qwen Token Plan matrix without publishing account data or unsanitized provider responses.

These checks improve provider-specific confidence but are not treated as blockers for publishing the reviewed source as an open-source release candidate.

## Publication sequence

1. Reduce the reviewed publication tree to one clean root commit and move the private release-candidate tag to that commit.
2. Verify the root history, licenses, privacy boundaries, release assets, Windows PowerShell 5.1 suite, and full-history Gitleaks job.
3. Change visibility only after the private release candidate and CI pass.
4. Immediately verify public clone/install behavior, GitHub media rendering, security reporting, and `main` protection.
