# WorkSync Code Review (Copilot)

## Findings (ordered by severity)

### 1) High: README latest-release download URL points to an asset CI does not upload
**Why it matters**
The primary download command requests a filename that is never produced or attached by the release workflow.

**Evidence**
- README requests `WorkSync-arm64.tar.gz`: [README.md](README.md#L48-L51)
- The release job uploads `build/WorkSync-*.tar.gz`: [.github/workflows/ci.yml](.github/workflows/ci.yml#L70-L74)
- The packaging script names the artifact `WorkSync-${VERSION}-${ARCH}.tar.gz`: [scripts/build-app.sh](scripts/build-app.sh#L117-L121)
- On tag `v0.1.0`, `git describe --tags` yields `v0.1.0`, producing `WorkSync-v0.1.0-arm64.tar.gz`. The release body uses this versioned form correctly: [.github/workflows/ci.yml](.github/workflows/ci.yml#L86-L89)

**Impact**
- A fresh user following the README gets a GitHub 404 from the recommended release URL.
- This breaks the main binary-distribution path despite a successful release build.

**Recommendation**
Make the README URL match the actual versioned artifact, or upload a stable alias such as `WorkSync-arm64.tar.gz` in addition to the versioned artifact. The stable alias is better for the `releases/latest` URL.

---

### 2) High: Release installation documents `worksync` commands without installing the CLI binary on `PATH`
**Why it matters**
The downloaded artifact contains an app bundle, but the README immediately tells users to run `worksync init`, `worksync calendars`, and other commands. No installation step creates that command or adds the bundle's inner executable to `PATH`.

**Evidence**
- README instructs release users to extract the app and then uses `worksync` as a command: [README.md](README.md#L48-L52), [README.md](README.md#L71-L83)
- The packaging script identifies the CLI path as `build/WorkSync.app/Contents/MacOS/worksync`, but does not install or symlink it: [scripts/build-app.sh](scripts/build-app.sh#L124-L125)
- The specification requires a small install step or README instruction for putting the inner binary on `PATH`: [SPEC.md](SPEC.md#L66-L67)

**Impact**
- Users following the release README will get `command not found: worksync` unless they manually discover the inner bundle path.
- The documented first-run flow cannot be completed as written.

**Recommendation**
Add an explicit install step after extraction, such as a user-local symlink in `~/bin` plus a `PATH` note, or document commands using `WorkSync.app/Contents/MacOS/worksync`.

## Residual Risks

### Medium: Release packaging was validated locally, but GitHub Actions publication was not observed
The local release path passed, including bundle assembly, SDK restamping, ad-hoc signing, signature verification, and LaunchServices registration. The actual `macos-26` runner and GitHub Release attachment remain external CI behavior and should be checked on the tagged release page.

### Low: Documentation has no single stable artifact-naming contract
The release body uses a versioned filename while the README uses a supposed stable `latest` filename. A single documented naming policy would prevent this drift from recurring.

## Snapshot (Milestone 5 Delta)
- Review type: Delta review (M4 -> M5)
- Baseline commit: `7d287e85706f960038006c28bdc587a807b0eafb` (`7d287e8`)
- Current commit reviewed: `8ff1525890feccd4e97b53b8e61dd1d3a59d2e11` (`8ff1525`)
- M5 landing commit: `aa4f487` (`v0.1.0`) - README, macOS 26 release workflow, and tag/version guard
- Close-out commit: `8ff1525`
- Working tree at review time: clean
- Review date: 2026-08-14

## Scope Reviewed
- README installation, first-run, CLI, and release instructions
- GitHub Actions build/test/release workflow
- version guard and artifact naming
- example config generation and `worksync init`
- per-config last-run state
- M4 review fixes included immediately before M5

## Verification Run
- `swift test`: **151 tests, 0 failures**
- `swiftformat --lint .`: **0 files require formatting**
- `scripts/build-app.sh --adhoc --no-tar`: passed release build, SDK restamp, signing, verification, and LaunchServices registration

## Improvements Confirmed
- M4 review findings were addressed before M5:
  - reactive status-icon observation is present in [Sources/worksync/MenuBar/StatusItemController.swift](Sources/worksync/MenuBar/StatusItemController.swift#L330-L349)
  - menu-bar launch-at-login controls and per-config login state are present in [Sources/worksync/MenuBar/MenuBarModel.swift](Sources/worksync/MenuBar/MenuBarModel.swift#L69-L118)
- Example config has generation/parity tests: [Tests/WorkSyncCoreTests/ExampleConfigTests.swift](Tests/WorkSyncCoreTests/ExampleConfigTests.swift)
- The release workflow validates the tag against `CFBundleShortVersionString`: [.github/workflows/ci.yml](.github/workflows/ci.yml#L60-L68)

## Assessment
The M5 code and local release checks are healthy, but the distribution instructions are not executable as written. Fix the asset URL and CLI installation instructions before treating the release experience as complete.
