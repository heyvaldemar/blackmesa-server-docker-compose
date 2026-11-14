# Black Mesa server using Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/blackmesa-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/blackmesa-server-docker-compose/actions/workflows/deployment-verification.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14897/badge)](https://www.bestpractices.dev/projects/14897)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Black Mesa deathmatch server, pinned by digest, locked to `dm_crossfire` — the modern remake of the Half-Life map with the tactical-nuke button — with the details that only show up after running one.

```bash
git clone https://github.com/heyvaldemar/blackmesa-server-docker-compose
cd blackmesa-server-docker-compose
cp .env.example .env && $EDITOR .env          # an rcon password
docker compose -f blackmesa-server-docker-compose.yml -p blackmesa up -d
```

The game is baked into the image, so the first start is a 16 GB pull and then a map load. Watch it:

```bash
docker compose -p blackmesa logs -f blackmesa-server
docker compose -p blackmesa ps          # healthy once the game answers A2S_INFO
```

Everyone who joins needs to own Black Mesa. There are no bots: this is player-versus-player only.

## What this file knows that a fresh one does not

**The health check asks the game, not its process.** `tools/healthcheck.sh` sends A2S_INFO, the query every server browser sends, to the game port and is healthy only on the engine's reply. Up to v1.2.2 it looked for `srcds_linux` in `/proc`, and on Docker Engine 29.4.2 that stayed green over a server with no socket at all (below). A hung or stopped game keeps its process too, and the log is not read either. A map change silences it for seconds; one check tries twice, and Docker allows three misses at a 60-second interval. Each check ends within 7 seconds. **It asks from inside the container**, at the address it answers on (the one it is bound to, or the container's own when it binds 0.0.0.0, as Left 4 Dead 2 does): healthy proves the server answers there, not that the port is published on the host or open in your firewall. Check that from outside, with a server browser.

**The map cannot drift.** `mp_timelimit 0` and `mp_fraglimit 0` on the command line mean the map never changes on its own, and the one-entry `mapcycle.txt` is mounted at both paths srcds may read it from, because one copy in the wrong place is a rotation that silently does not exist. For a rotating server, set a time limit in `.env` and add maps.

**Free-for-all is pinned.** The image's own cfg ships `mp_teamplay 1`, which flipped a running server into team mode in the middle of a session. server.cfg sets it to 0.

**The log is flushed per line, and stays one file.** The engine buffers the log and flushes only when the file closes, so a quiet server writes a file that reports zero bytes while people are talking; two players chatted for ten minutes while `ls` showed 0. `sv_logflush 1` fixes that. server.cfg is also exec'd at every map load, and a second `log on` closes the current file and opens a fresh one, which is how a server ends up with 141 log files in a day; `sv_log_onefile 1` keeps one.

**The published port matches the port the server binds.** Steam's list records what the server bound, not what you forwarded. Publish 27016 for a server on 27015 and the list hands players an address where a different server answers.

**The memory ceiling is measured, not guessed.** A deathmatch server peaked at 865 MB; the 3 GB limit exists so a leak here cannot get some other container killed instead.

**Docker Engine 29.4.2 cuts this server off the network, and only that release does.** Its default seccomp profile answers the 32-bit `socketcall` system call with "not implemented" ([moby/moby#52506](https://github.com/moby/moby/issues/52506); for GitHub Actions, the ubuntu-26.04 runner image ships it: [actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790), with the move to 29.7.2 in [actions/runner-images#15205](https://github.com/actions/runner-images/pull/15205)), and Black Mesa's srcds is a 32-bit program that makes every socket with it. The server starts, stays up, and opens no socket at all: no player can reach it, A2S gets no answer, rcon gets no connection, and the health check up to v1.2.2, which looked for the process, stayed green; the one since v1.3.0 asks the game and goes red, and CI reproduces exactly this to prove it. Measured in [a CI run on GitHub's ubuntu-26.04 runner, which ships 29.4.2](https://github.com/heyvaldemar/tf2-server-docker-compose/blob/main/docs/evidence/docker-29.4.2-socketcall.md): on the default profile healthy, no A2S answer and no rcon after 90 seconds; with the profile Docker 29.4.3 ships, both answered. 29.4.3 reverted the rule, and Ubuntu 26.04's own `docker.io` (27.5.1) never had it. Check with `docker version --format '{{.Server.Version}}'` and upgrade; until you can, point [`seccomp-profile` in `daemon.json`](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file) at [moby/profiles seccomp v0.2.3](https://github.com/moby/profiles/blob/836ae4d37ef2ec995c77c99fc55f5b5f3af3a897/seccomp/default.json) and restart Docker.

## Hiding your home address

If you run this at home, the server's address is in Steam's public list. To keep it off, put the game container in the network namespace of a WireGuard sidecar that dials out to a cheap relay: [game-server-wireguard-relay-docker-compose](https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose). One warning if you go that way: `network_mode: host` hangs srcds at Steam initialisation on a machine with more than one interface, with no error. The sidecar's namespace is bridge-style, which is why these servers start at all.

## Administration

```bash
# rcon, using the password from .env
tools/rcon.sh status
tools/rcon.sh changelevel dm_gasworks
```

Up to v1.2 this said `docker compose -p blackmesa exec blackmesa-server rcon status`. The image has no rcon program, so that command could only fail, and nothing ever ran it. `tools/rcon.sh` speaks the rcon protocol from the server's network namespace, with python from a pinned image, and takes the password from `.env` on stdin rather than the command line where `ps` would show it. CI boots the real server from this file and runs it: `status` must return the hostname line, and a wrong password must be refused.

## Updating

The pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the image this repository has tested. The tag is `latest` because upstream publishes no version numbers: the digest is the version. When the game updates, Laclede's LAN rebuilds the image, the daily freshness check goes red, and the pin moves deliberately. `./update.sh` does that on purpose: it moves to the latest release tag, refuses to cross a major unattended, and names any new required variable before anything has moved.

## Testing

CI boots the real server on every push, from the 16 GB image, and then:

- runs `tools/rcon.sh status` and needs the hostname line back, and a wrong password refused;
- runs the health check in the pinned image against a stand-in that answers A2S_INFO, answers after a challenge, answers after a challenge with a newline byte in it (the request must go out as one 29-byte datagram), stays silent, or is not there: healthy, healthy, healthy, unhealthy within 7 seconds, unhealthy (`tests/e2e-healthcheck.sh`);
- changes the map over rcon and needs the health check to answer again on the new map, with Docker's status healthy throughout;
- gives the RCON password a value of its own and looks for it in `docker compose logs`, on every command line in the container and in the host's `ps`, after the first start, while `tools/rcon.sh` runs and after a restart, naming the place, never the value (`tests/secret-probe.sh`);
- times a `docker compose stop` and reads its exit code (`tests/clean-stop.sh`). Measured: 30 seconds of the 30-second grace period and exit 137, Docker's SIGKILL, because `srcds_run`, process 1 here, does not pass SIGTERM on. Black Mesa keeps no world, so nothing is lost; a stop or restart simply waits out the grace period;
- **stops the game process** with SIGSTOP: the process stays, the old `/proc` check still passes, and the health check must fail; after SIGCONT it must pass again;
- **gives the container the seccomp profile Docker 29.4.2 shipped**: the server runs with no socket, the old check passes, and the health check must fail saying nothing is bound; recreated without it, the server must answer again.

All of it alongside shell and workflow linting, a Trivy scan of the pinned image, and a daily check that the pin still resolves to what upstream publishes.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · CNCF Ambassador · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
