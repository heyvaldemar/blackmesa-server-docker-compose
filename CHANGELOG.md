# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **CI looks for the RCON password everywhere it could leak to.** `tests/secret-probe.sh` gives it a value of its own and fails on it in `docker compose logs`, on any command line in the container or in the host's `ps`, after the first start, while `tools/rcon.sh` runs and after a restart; it names the variable and the place, never the value. It found nothing ([run 43617761533](https://github.com/heyvaldemar/blackmesa-server-docker-compose/actions/runs/43617761533)).
- **A stop is measured.** `tests/clean-stop.sh` times `docker compose stop` on the real server: 30 seconds of the 30-second grace period, exit 137, Docker's SIGKILL. `srcds_run` is process 1 and does not pass SIGTERM on, so every stop waits out the grace period. Black Mesa keeps no world to save; the README says so.

### Fixed

- **The health check could cut its own request in two.** bash writes printf's output line by line, so the query echoing the server's challenge went out as two datagrams whenever the challenge held a newline byte (0x0a), and that try went unanswered; one check in a few thousand, which the retries covered. The request now goes to a file first and out in one write. `tests/e2e-healthcheck.sh` proves it against a stand-in whose challenge holds one: the old check sends 26 and 3 bytes and stays unhealthy, this one one datagram of 29.

- **An index pushed again over the same build is no longer reported as drift.** The daily pin check compared each pin with the digest the tag's index has now and failed on any difference, so a publisher re-pushing the index over the very same images (a platform added, an attestation rewritten) turned it red for an image nobody rebuilt, and no pin would ever move to turn it green. It now also compares the linux/amd64 build under both digests, the one CI runs and proves: the same build passes with a notice naming both digests, a new build fails as drift exactly as before, and a build that cannot be read still fails.

## [1.3.0] - 2026-11-08

### Changed

- **The health check asks the game, not its process.** It looked for `srcds_linux` in `/proc`, and on Docker Engine 29.4.2 that stayed green over a server with no socket at all (run 42503040679); a hung or stopped game keeps its process too. `tools/healthcheck.sh`, mounted read-only, now sends A2S_INFO to the game port at the address it answers on (the one it is bound to, or the container's own when it binds 0.0.0.0, as Left 4 Dead 2 does) and is healthy only on the engine's reply; it handles the challenge Source servers may answer with first, tries twice for a map change, and ends within 7 seconds. It asks from inside the container, so it does not prove the port is published on the host or open in a firewall; the README says so. CI runs it in the pinned image against a stand-in, and on the real server changes the map and needs it answering again, stops the game with SIGSTOP and needs it red, and gives the container Docker 29.4.2's seccomp profile and needs it red with nothing bound while the old check stays green.
- **The README's Testing section said CI does not boot the game.** It has since v1.2.2; the section now lists what the boot job checks.
## [1.2.2] - 2026-11-08

### Fixed

- **The README names Docker Engine 29.4.2, which cuts this server off the network.** That release alone answers the 32-bit `socketcall` system call with ENOSYS in its default seccomp profile ([moby/moby#52506](https://github.com/moby/moby/issues/52506)); Black Mesa's srcds is 32-bit, so on it the server stays up and healthy and opens no socket: no A2S answer, no rcon (blackmesa-server-docker-compose run 42503040679, default profile against the profile Docker 29.4.3 ships). The fix is Docker 29.4.3 or later, or the daemon's `seccomp-profile` pointed at 29.4.3's profile. GitHub's ubuntu-26.04 runner image ships 29.4.2 ([actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790)), so the new CI job below gives its daemon 29.4.3's profile on that version only.
- **rcon works as the README says.** It said `docker compose -p blackmesa exec blackmesa-server rcon status`, and the pinned image has no rcon program (`command -v rcon` inside the running server is empty), so the command could only fail. `tools/rcon.sh` speaks the protocol from the server's network namespace, with python from a pinned image, and takes the password from `.env` on stdin, never in argv. A new CI job boots the real server from this compose file with a random RCON password and runs it: `status` must return the hostname line and a wrong password must be refused. The password itself, read from `cfg/secrets/rcon.cfg` since 1.2.1, was already accepted over the protocol (measured in tf2-server-docker-compose run 42499988775).
## [1.2.1] - 2026-11-08

### Security

- **The RCON password is no longer on the server's command line.** It was passed to srcds as `+rcon_password <password>`, so it sat in its arguments for as long as the server ran, where every user on the host reads it with `ps` (`/proc/<pid>/cmdline` is world-readable, and the host sees every container's processes). The compose file now hands it to the container as an environment variable; a short entrypoint writes it with the shell's own `printf` into `cfg/secrets/rcon.cfg`, on a tmpfs so it never touches a disk, mode 600, and the command line carries `+exec secrets/rcon.cfg` in its place. A password holding a double quote, which a Source config line cannot carry, stops the start with a message instead of being cut. The game image is too large for a CI runner, so the new `tests/e2e-rcon-secret.sh` runs the compose file's own entrypoint, command and tmpfs against a stand-in `srcds_run` and reads every command line on the runner and in the container: none may carry the password. Against the previous compose file the same test fails all seven of its checks.

### Changed

- **The freshness check has its own workflow, Pin Freshness.** It ran inside Deployment Verification, whose badge is the one at the top of this README. Across the fleet, nine red runs in ten were a pin one version behind - which the fleet's triage moves within the day - and a reader cannot tell that from a stack that does not boot. The badge now says whether the stack boots. The job itself is unchanged.

### Fixed

- **`update.sh` no longer stops without a word when a release adds a variable and no compose file requires one.** The search for `${VAR:?}` came back empty, and under `pipefail` that empty result ended the script with status 1 right after it listed the new variables.
- **`update.sh` stops on a `.env` it cannot read, before the checkout.** It used to fall through: every new required variable read as "not set", or, with none, the tree moved to the new tag and `docker compose up` failed on the permission. Now it names the file, its owner and mode, and changes nothing.

## [1.2.0] - 2026-09-22

### Added

- **`BLACKMESA_SERVER_TIMEZONE`: the game gets the household clock too.** Every timestamp this server writes — a ban, a join, the crash it leaves behind — is read next to a log line from somewhere else, and two clocks turn that into arithmetic. Six of this fleet's eleven game templates already carried the setting and this one did not. It defaults to UTC, which is now a choice rather than an accident, and the image carries the whole tz database so any zone name works. Measured against the pinned image: unset gives `UTC`, set gives the zone asked for.

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

[Unreleased]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/blackmesa-server-docker-compose/releases/tag/v1.0.0
