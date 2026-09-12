# ADR-0011 — The Homebrew cask sha256 is taken from the published asset, never a local build

Status: accepted
Date: 2026-09-12

## Context

The Homebrew tap (`gAmUssA/homebrew-worksync`) is a separate repo. A GitHub
release does not update it. `livecheck` only reports a new version. Without a
bump job, every tagged release would ship while `brew install --cask` still
handed users the previous one.

The cask's `sha256` has to describe the bytes users download. Hashing the
artifact the job just built would pass CI and fail on every user's machine if
the uploaded asset differed.

## Decision

The `bump-tap` job in `.github/workflows/ci.yml` runs on `v*` tags after
`release`. It `curl`s
`WorkSync-${TAG}-arm64.tar.gz` from the GitHub Releases URL, hashes that
file (`shasum -a 256`), and writes `version` and `sha256` into
`Casks/worksync.rb`.

An older tag must not downgrade a newer cask: before edit and after a
rejected push, the job compares versions with `sort -V` and exits 0 if the
tap already carries a newer version. Missing `HOMEBREW_TAP_TOKEN` warns and
skips rather than failing a release that already published.

## Consequences

- `needs: release` gates the job on release completion, not independently
  confirmed asset visibility. If the download is unavailable, `curl -f` fails
  the step before the cask is edited. The workflow has no local-build fallback.
- A local or CI-built tarball must never be substituted for the downloaded
  asset. Doing so would make the cask lie.
- The no-downgrade guard means a late or retried older tag is a no-op, not a
  rollback of `brew install`.
- Without the token secret, users keep getting the previous cask until
  someone bumps the tap by hand. The job says so in the log.
