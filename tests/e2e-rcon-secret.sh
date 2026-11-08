#!/bin/bash
# Does the RCON password stay off every command line?
#
# It used to be `+rcon_password <password>` on srcds's command line, where it
# sat for as long as the server ran: every user on the host reads a process's
# arguments with ps. The compose file's entrypoint now writes it into
# cfg/secrets/rcon.cfg and the command carries `+exec secrets/rcon.cfg`.
#
# The game image is too large for a runner, so this runs the compose file's own
# entrypoint, command, tmpfs and environment (docker compose run, not a copy)
# with a stand-in srcds_run that records what it was given and stays up. While
# it runs, every command line on this machine and in the container is read for
# the password, compared through a file so it is never printed.
#
#   ./tests/e2e-rcon-secret.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
COMPOSE_FILE=blackmesa-server-docker-compose.yml
PROJECT="bmsrcon$$"
WORK="$(mktemp -d)"
PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }
cleanup() {
  docker rm -f "$PROJECT-run" >/dev/null 2>&1
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" -f "$WORK/override.yml" down -v >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/app/bms/cfg"
chmod -R 0777 "$WORK/app"
# The stand-in stays up as itself, not exec'ing into sleep, so its own
# arguments are there to be read for as long as it runs, as srcds's are.
cat > "$WORK/srcds_run" <<'SH'
#!/bin/sh
case " $* " in *" +exec secrets/rcon.cfg "*) echo "srcds_run: +exec secrets/rcon.cfg given" ;; esac
case " $* " in *" +rcon_password "*) echo "srcds_run: +rcon_password given" ;; esac
stat -c "rcon.cfg: %a" bms/cfg/secrets/rcon.cfg
sleep 60
SH
chmod 755 "$WORK/srcds_run"
cat > "$WORK/override.yml" <<YML
services:
  blackmesa-server:
    image: debian:stable-slim
    user: "1000:1000"
    working_dir: /app
    volumes:
      - $WORK/app:/app
      - $WORK/srcds_run:/app/srcds_run:ro
YML

# start <password>: the stack's own entrypoint and command, detached
start() {
  docker rm -f "$PROJECT-run" >/dev/null 2>&1
  BLACKMESA_SERVER_RCON_PASSWORD="$1" docker compose -p "$PROJECT" -f "$COMPOSE_FILE" -f "$WORK/override.yml" \
    run -d --name "$PROJECT-run" blackmesa-server >/dev/null
}

echo "=== the RCON password, while the server runs ==="
PW="$(openssl rand -hex 16)"
PW_FILE="$WORK/pw"; ( umask 077; printf '%s\n' "$PW" > "$PW_FILE"; printf 'rcon_password "%s"\n' "$PW" > "$WORK/expected" )
start "$PW"
got=""
for _ in $(seq 1 30); do
  got="$(docker logs "$PROJECT-run" 2>&1)"
  case $got in *"rcon.cfg"*) break ;; esac
  sleep 1
done
# shellcheck disable=SC2009  # every command line on the machine, not one process
host=$(ps -eo args= | grep -cF -f "$PW_FILE" || true)
# shellcheck disable=SC2016  # expanded by the container's shell
ctr=$(docker exec "$PROJECT-run" sh -c 'for f in /proc/[0-9]*/cmdline; do tr "\000" " " < "$f" 2>/dev/null; echo; done' | grep -cF -f "$PW_FILE" || true)
cfg_ok=no
if docker exec "$PROJECT-run" cat bms/cfg/secrets/rcon.cfg 2>/dev/null | cmp -s - "$WORK/expected"; then cfg_ok=yes; fi
inspect=$(docker inspect -f '{{json .Config.Cmd}} {{json .Args}}' "$PROJECT-run" | grep -cF -f "$PW_FILE" || true)

# What srcds was given is reported by the stand-in as two yes/no lines, never
# echoed back: on a broken file its arguments are the password.
case $got in
  *"+exec secrets/rcon.cfg given"*) pass "srcds is started with +exec secrets/rcon.cfg" ;;
  *) fail "srcds was not started with +exec secrets/rcon.cfg" ;;
esac
case $got in
  *"+rcon_password given"*) fail "srcds was still given +rcon_password on its command line" ;;
  *) pass "and not with +rcon_password" ;;
esac
if [ "$host" = 0 ] && [ "$ctr" = 0 ]; then
  pass "no command line on the host or in the container carries the password"
else
  fail "the password is on a command line: $host on the host, $ctr in the container"
fi
if [ "$inspect" = 0 ]; then pass "nor the container's recorded command"; else fail "the password is in the container's recorded command"; fi
if [ "$cfg_ok" = yes ]; then pass "cfg/secrets/rcon.cfg carries exactly the password line"; else fail "cfg/secrets/rcon.cfg does not carry the password line"; fi
case $got in
  *"rcon.cfg: 600"*) pass "and only its owner can read it" ;;
  *) fail "rcon.cfg is not there with mode 600" ;;
esac

echo "=== a password a config line cannot carry ==="
start 'with"quote'
rc=""
for _ in $(seq 1 30); do
  rc="$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$PROJECT-run" 2>/dev/null)"
  case $rc in exited*) break ;; esac
  sleep 1
done
log="$(docker logs "$PROJECT-run" 2>&1)"
case "$rc|$log" in
  "exited 1|"*"double quote"*) pass "a double quote stops the start, and says why" ;;
  *) fail "a double quote did not stop the start ($rc)" ;;
esac

echo
echo "=== $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ]
