# Release checklist

Use this checklist for each candidate. Check results in its GitHub Actions run and release notes; previous releases do not prove the next package.

## Candidate

- [ ] Integrate onto current public main without rewriting history.
- [ ] Review the complete diff, new runtime helpers, tests and documentation.
- [ ] Run the complete Windows PowerShell 5.1 suite with isolated application data.
- [ ] Preserve fullscreen hiding and provider opt-in defaults.
- [ ] Run Gitleaks and exclude runtime data, saved credentials, logs and personal screenshots.
- [ ] Document provider and physical-device validation limits.

## GitHub

- [ ] Open a normal pull request and pass the required `powershell-51` and `secret-scan` checks.
- [ ] Merge with maintainer authorization and verify the main-branch checks.
- [ ] Build the release archive from the exact merged commit.
- [ ] Extract the complete archive to a Windows path containing spaces and rerun all tests.
- [ ] Verify file inventory, source hashes, relative documentation links and the package secret scan.
- [ ] Publish the authorized version as a prerelease, with a SHA-256 checksum and clear upgrade instructions.
- [ ] Download the published assets and confirm their hashes against the tested package.
- [ ] Verify public README media and release links before announcing the release.

See [release readiness](OPEN_SOURCE_READINESS.md) for local evidence and remaining manual validation. Keep runtime settings and credentials outside the archive. Publication does not authorize an X post.
