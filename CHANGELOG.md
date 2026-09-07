# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.1.0] - 2026-09-07

### Added

- **`update.sh`: move between release tags on purpose.** It updates to the latest release (a combination this repository's CI has booted and smoke-tested), refuses to cross a major version unattended, refuses to run over local changes, and names any new required variable before anything has moved. `--dry-run` says what would happen.

hes the game exactly rather than as a substring.**
  Two commands run in the container: `srcds_linux`, the game, and `srcds_run`,
  its restart wrapper. A substring search is satisfied by either, so the game
  can crash and leave the wrapper standing while the container reports
  healthy. `tests/e2e-healthcheck.sh` proves the distinction against a real
  container, with no game download.
- **A map that cannot drift.** Time and frag limits of zero and a one-entry
  rotation mounted at both paths srcds may read it from, because one copy in
  the wrong place is a rotation that silently does not exist.
- **Free-for-all pinned in server.cfg.** The image's own cfg ships
  `mp_teamplay 1`, which flipped a running server into team mode mid-session.
- **A log that is flushed per line and stays one file.** The engine buffers
  and flushes only on close, so a quiet server reports zero bytes while people
  are talking; and server.cfg is exec'd at every map load, so a second
  `log on` opened a fresh file each time — 141 in one day.
- **The published port equal to the port the server binds**, and **measured
  limits**: a deathmatch server peaked at 865 MB, and the 3 GB ceiling exists
  so a leak here cannot get some other container OOM-killed in its place.
- **Deployment Verification CI**: shell and workflow linting, a Trivy scan of
  the pinned image, a daily freshness check on the pin, and the health-check
  suite. It deliberately does not boot the game: the image is 16 GB
  compressed, and a test that pretends a runner can hold it never runs.

[Unreleased]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/releases/tag/v1.0.0
