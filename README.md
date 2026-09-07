# Black Mesa server using Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/blackmesa-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/blackmesa-server-docker-compose/actions/workflows/deployment-verification.yml)
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
docker compose -p blackmesa ps          # healthy once srcds is up
```

Everyone who joins needs to own Black Mesa. There are no bots: this is player-versus-player only.

## What this file knows that a fresh one does not

**The health check matches the game exactly, not as a substring.** Two commands run in this container: `srcds_linux`, the game, and `srcds_run`, the script that restarts it. A check for the substring `srcds` is satisfied by either, so the game can crash and leave the wrapper standing while the container reports healthy — and docker does not restart an unhealthy container on its own, so nothing else catches it either. `tests/e2e-healthcheck.sh` proves the distinction against a real container.

**The map cannot drift.** `mp_timelimit 0` and `mp_fraglimit 0` on the command line mean the map never changes on its own, and the one-entry `mapcycle.txt` is mounted at both paths srcds may read it from, because one copy in the wrong place is a rotation that silently does not exist. For a rotating server, set a time limit in `.env` and add maps.

**Free-for-all is pinned.** The image's own cfg ships `mp_teamplay 1`, which flipped a running server into team mode in the middle of a session. server.cfg sets it to 0.

**The log is flushed per line, and stays one file.** The engine buffers the log and flushes only when the file closes, so a quiet server writes a file that reports zero bytes while people are talking; two players chatted for ten minutes while `ls` showed 0. `sv_logflush 1` fixes that. server.cfg is also exec'd at every map load, and a second `log on` closes the current file and opens a fresh one, which is how a server ends up with 141 log files in a day; `sv_log_onefile 1` keeps one.

**The published port matches the port the server binds.** Steam's list records what the server bound, not what you forwarded. Publish 27016 for a server on 27015 and the list hands players an address where a different server answers.

**The memory ceiling is measured, not guessed.** A deathmatch server peaked at 865 MB; the 3 GB limit exists so a leak here cannot get some other container killed instead.

## Hiding your home address

If you run this at home, the server's address is in Steam's public list. To keep it off, put the game container in the network namespace of a WireGuard sidecar that dials out to a cheap relay: [game-server-wireguard-relay-docker-compose](https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose). One warning if you go that way: `network_mode: host` hangs srcds at Steam initialisation on a machine with more than one interface, with no error. The sidecar's namespace is bridge-style, which is why these servers start at all.

## Administration

```bash
docker compose -p blackmesa exec blackmesa-server rcon status
docker compose -p blackmesa exec blackmesa-server rcon changelevel dm_gasworks
```

## Updating

The pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the image this repository has tested. The tag is `latest` because upstream publishes no version numbers: the digest is the version. When the game updates, Laclede's LAN rebuilds the image, the daily freshness check goes red, and the pin moves deliberately.

## Testing

`tests/e2e-healthcheck.sh` runs five assertions against a real container and needs no game download: the exact check is green with the game running, the substring check is green too, and after the game is killed the exact one goes red while the substring one stays green with the wrapper still standing.

CI runs it on every push alongside shell and workflow linting, a Trivy scan of the pinned image, and a daily check that the pin still resolves to what upstream publishes.

CI does not boot the game. The image is 16 GB compressed, which is more than a GitHub runner has to give, and a test that pretends otherwise is a test that never runs.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
