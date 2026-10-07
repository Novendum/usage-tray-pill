# Contributing

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
For usage help and safe bug-reporting guidance, see [SUPPORT.md](SUPPORT.md).

## Development setup

Use Windows 11 with Windows PowerShell 5.1. Clone the repository to any directory; source code and tests must not depend on a fixed local path.

Run the full test suite before proposing a change:

```powershell
.\tests\Test-UsageTrayPill.ps1
```

## Pull requests

Application code lives in `src/`, setup and build scripts in `scripts/`, and developer tests in `tests/`. Keep `Start-UsageTrayPill.cmd` as the root entry point.

Build a users' package after the test suite passes:

```powershell
.\scripts\Build-ReleasePackage.ps1 -Version 0.1.0-rc.5-local
```

The explicit file list excludes tests, build tools, internal design notes and promotional media. Versioned outputs go to `dist/`; existing packages are never overwritten. Building a package does not publish a GitHub release.

- Keep provider adapters fail-safe and preserve the last valid usage snapshot.
- Add a regression test for behavior changes.
- Do not commit runtime data, credentials, account identifiers, logs, or screenshots containing personal information.
- Do not add network destinations or credential access without updating `PRIVACY.md`, `SECURITY.md`, and the tests.
- Keep provider trademark assets separate from UTP's own identity.
- Include provenance, a redistributable license, and an exact source revision for every bundled third-party asset.

## Provider compatibility

ChatGPT/Codex and Claude integrations depend partly on local provider interfaces. Document the provider version used for verification and handle missing fields without replacing valid cached values with empty data.
