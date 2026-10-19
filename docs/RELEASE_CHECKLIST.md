# Release checklist

Use this checklist for each candidate. Check results in its GitHub Actions run and release notes; previous releases do not prove the next package.

## Candidate

- [ ] Integrate onto current public main without rewriting history.
- [ ] Review the complete diff, new runtime helpers, tests and documentation.
- [ ] Run the complete Windows PowerShell 5.1 suite with isolated application data.
- [ ] Preserve fullscreen hiding and provider opt-in defaults.
- [ ] Run Gitleaks and exclude runtime data, saved credentials, logs and personal screenshots.
- [ ] Document provider and physical-device validation limits.
- [ ] Set `$script:AppVersion` to the release version and add its CHANGELOG section. The builder refuses a release version that differs from the runtime, and the in-app updater rejects a ZIP that reports another version.

## GitHub

- [ ] Open a normal pull request and pass the required `powershell-51` and `secret-scan` checks.
- [ ] Merge with maintainer authorization and verify the main-branch checks.
- [ ] Build the release archive from the exact merged commit.
- [ ] Run the complete source test suite, including package construction and validation. Extract the users' ZIP to a Windows path containing spaces and run its offline runtime SelfTest; developer tests must not ship in the users' ZIP.
- [ ] Verify file inventory, source hashes, relative documentation links and the package secret scan.
- [ ] Publish the authorized version as a prerelease on tag `v<version>`, with the assets `UsageTrayPill-<version>-windows.zip` and `SHA256SUMS.txt` and clear upgrade instructions. **Check for updates** only offers releases with exactly these names.
- [ ] Download the published assets and confirm their hashes against the tested package.
- [ ] On an installation of the previous release (rc.8 or later), run **Check for updates** and confirm that it offers, installs and restarts the new version.
- [ ] Verify public README media and release links before announcing the release.

See [release readiness](OPEN_SOURCE_READINESS.md) for local evidence and remaining manual validation. Keep runtime settings and credentials outside the archive. Publication does not authorize an X post.
