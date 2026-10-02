# Release checklist

October 2026 update. Each checkmark applies only to evidence recorded in [Open-source readiness](OPEN_SOURCE_READINESS.md), not to every future commit.

## Local candidate

- [x] README separates quick start, optional setup, requirements and limitations.
- [x] Privacy, security and architecture describe the new collection paths.
- [x] Product images use isolated synthetic values; generated cover is identified as brand artwork.
- [x] Online history and earlier demo/public-status fixes are identified for preservation.
- [x] Final candidate passes the aggregate Windows PowerShell 5.1 suite after extraction to a path with spaces.
- [x] Final candidate passes Gitleaks and a runtime-data/credential filename check.
- [x] File manifest and visual-asset hashes match the reviewed package.

## Provider compatibility

- [x] Local signed-in reads were observed for Codex, Claude CLI 2.1.286, Antigravity CLI 1.2.14 and OpenCode Go during October development.
- [x] Offline regressions cover authentication pauses, retries, missing data, enable/disable behavior and credential boundaries.
- [ ] Full manual OpenCode Go setup, expired-key, subscription, rate-limit and cross-user DPAPI matrix.
- [ ] Full manual Qwen plan/session matrix. Qwen remains optional and off by default.
- [ ] Fresh-user Windows installation and multiple physical display/scaling combinations.

Fixtures and an owner session do not establish universal provider compatibility. Retain these limitations in release notes.

## GitHub publication

- [x] Integrate onto current public main through an authorized checkout/branch, retaining existing history.
- [ ] Review the complete diff and new files/media; scan the actual proposed Git history.
- [ ] Both required GitHub checks pass on the update.
- [ ] Verify README links, images and install instructions in GitHub.
- [ ] Merge after maintainer authorization.
- [ ] Build and test the final archive from the merged commit; choose and publish the release after authorization.
- [ ] Check the public download before posting the announcement.

Historical July/August checkmarks are not proof for this update. Local preparation does not create a tag, release or history rewrite.
