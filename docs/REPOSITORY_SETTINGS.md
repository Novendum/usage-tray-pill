# Repository settings

Read-only GitHub review: 2026-10-02. These are observed settings, not instructions to recreate the repository.

## Verified online

- [Novendum/usage-tray-pill](https://github.com/Novendum/usage-tray-pill) is public, MIT-licensed, with default branch `main`.
- Issues and private vulnerability reporting are enabled; Wiki and Discussions are disabled.
- A main-branch ruleset requires a pull request, linear history, resolved conversations and up-to-date `powershell-51` and `secret-scan` checks. Force pushes and deletion are blocked.
- Main commit `814714061b7f8d23f1f3346db940e195e5778c62` passed both jobs in [run 30903908068](https://github.com/Novendum/usage-tray-pill/actions/runs/30903908068).
- Tag `v0.1.0-rc.1` exists; no GitHub Release was listed.
- GitHub native secret scanning, push protection and Dependabot security updates are disabled. The required Gitleaks CI job is enabled. Additional protections require a maintainer decision.

## Updating the public repository

Preserve the existing public history. The previous private clean-root publication is complete and must not be repeated. If a local checkout has a different root, prepare an explicitly authorized integration checkout based on current online main, compare files and open a normal pull request. Do not force-push local history or overwrite online fixes.

The public demo attachment and public-release wording were repaired in earlier pull requests. Retain those fixes. Refresh the GitHub comparison before publishing; these observations are a dated snapshot.

## Release packaging

Build the final archive from the reviewed, merged commit. Include runtime scripts, native C# helpers, assets, licenses and documentation. Run the aggregate suite in Windows PowerShell 5.1 from the extracted archive, including a path with spaces. Scan its contents and the proposed Git history with Gitleaks.

Never attach runtime data, logs, saved connections, provider responses or account screenshots. A local candidate ZIP is not an official release. Tags, GitHub Releases and repository setting changes require their own maintainer action.
