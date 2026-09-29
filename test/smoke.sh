#!/bin/sh
# Smoke tests for a standalone BluOSNowPlaying binary, for example one from
# burrito_out/.
#
# A binary only runs on the platform it was built for, so pass the one matching
# this machine, which host_target below names:
#
#     test/smoke.sh burrito_out/bluos_now_playing_macos_arm64
#     test/smoke.sh burrito_out/bluos_now_playing_linux_x86_64
#
# Binaries come out of burrito_out/ without the executable bit for everyone but
# the owner, so chmod +x one before running this.
set -eu

BIN=${1:?usage: smoke.sh <path to bluos_now_playing binary>}
failures=0

# The Burrito target that matches this machine, used to point at the right
# binary when the one passed in is for another platform.
host_target() {
  case $(uname -s) in
    Darwin) os=macos ;;
    Linux) os=linux ;;
    MINGW* | MSYS* | CYGWIN*) os=windows ;;
    *) os=$(uname -s | tr '[:upper:]' '[:lower:]') ;;
  esac
  case $(uname -m) in
    arm64 | aarch64) cpu=arm64 ;;
    x86_64 | amd64) cpu=x86_64 ;;
    *) cpu=$(uname -m) ;;
  esac
  # Windows is only built for x86_64.
  [ "$os" = windows ] && cpu=x86_64
  echo "${os}_${cpu}"
}

HOST_TARGET=$(host_target)
# The Windows binary is the only one with a suffix.
HOST_BIN="burrito_out/bluos_now_playing_$HOST_TARGET"
[ "$HOST_TARGET" = windows_x86_64 ] && HOST_BIN="$HOST_BIN.exe"

report() {
  case $1 in
    ok) printf 'ok   %s\n' "$2" ;;
    *)
      report_body="FAIL $2"
      shift 2
      for line in "$@"; do report_body="$report_body
   $line"; done
      printf '%s\n' "$report_body"
      failures=1
      ;;
  esac
}

expect() {
  if [ "$2" = "$3" ]; then
    report ok "$1"
  else
    report fail "$1" "expected: $2" "actual:   $3"
  fi
}

# The server log is what explains a failure, and it disappears with $WORK, so
# print it before giving up. On GitHub Actions a job log is only readable by
# someone signed in to the site, so the same text goes to the step summary,
# which is public on a public repository.
diagnostics() {
  [ -f "$WORK/log" ] || return 0
  echo
  echo "# server log"
  tail -n 40 "$WORK/log" | sed 's/^/# /'
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo '## Server log'
      echo
      echo '```text'
      tail -n 40 "$WORK/log"
      echo '```'
    } >>"$GITHUB_STEP_SUMMARY"
  fi
}

echo "# smoke testing $BIN"
echo "# host target: $HOST_TARGET"

# The app writes .bluos_now_playing.json to the current directory, so run it
# from a scratch directory instead of the repository. That makes the caller's
# path relative to the wrong directory, so resolve it first.
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")
WORK=$(mktemp -d)
SERVER_PID=

# Burrito's launcher spawns the BEAM as a child and does not forward signals to
# it, so killing the launcher alone leaves the server running. Kill the child
# first and the launcher exits by itself, which also keeps the shell from
# printing a "Killed" job notice for it. Only available on macOS and Linux; on
# Windows a server left behind by a failed run has to be killed by hand.
kill_server() {
  [ -n "$SERVER_PID" ] || return 0
  if command -v pkill >/dev/null 2>&1; then
    pkill -9 -P "$SERVER_PID" 2>/dev/null || true
  fi
  i=0
  while kill -0 "$SERVER_PID" 2>/dev/null && [ "$i" -lt 20 ]; do
    i=$((i + 1))
    sleep 0.1
  done
  kill -9 "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=
}

cleanup() {
  kill_server
  cd / || true
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

# Burrito answers `maintenance meta` from the metadata embedded in the binary,
# without unpacking the payload, so it is a cheap way to find out what is being
# tested: the app and ERTS version, and the Zig target it was built for. Naming
# the build is the point, because a rebuilt binary that keeps running the
# previous payload otherwise looks exactly like one whose changes did land.
# It only answers for the host's own platform, since the operating system
# refuses to exec a binary built for another one, which makes it a pre-flight
# check that catches a mismatched binary before anything is started.
if META=$("$BIN" maintenance meta 2>&1); then
  meta_field() { printf '%s' "$META" | sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p"; }
  meta_target() { printf '%s' "$META" | sed -n 's/.*-Dtarget=\([^"]*\).*/\1/p'; }
  echo "# binary: $(meta_field app_name) $(meta_field app_version)," \
    "erts $(meta_field erts_version)," \
    "zig target $(meta_target)," \
    "built with zig $(meta_field zig_version)"
else
  case $META in
    *"Permission denied"*)
      report fail "the binary runs on this machine" "chmod +x it, then run this again"
      ;;
    *)
      report fail "the binary runs on this machine" \
        "this is a $HOST_TARGET machine, the binary is for another platform" \
        "try: test/smoke.sh $HOST_BIN"
      ;;
  esac
  echo "# failures" >&2
  exit 1
fi

# No PORT is set by the caller: pick a high one from the shell's own pid, so
# concurrent runs and a server the developer is already running do not collide.
PORT=$((40000 + $$ % 20000))

# Starts the binary and waits for the endpoint to answer, leaving the HTTP
# status in $status and the body in $WORK/body. The server is started from $WORK
# rather than in a subshell, so $! is the pid of the launcher itself.
cd "$WORK"
PORT="$PORT" "$BIN" >"$WORK/log" 2>&1 &
SERVER_PID=$!

status=000
i=0
while [ "$i" -lt 60 ]; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    status=dead
    break
  fi
  status=$(curl -s -o "$WORK/body" -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null) || status=000
  [ "$status" != 000 ] && break
  i=$((i + 1))
  sleep 1
done

if [ "$status" = dead ]; then
  # A mismatched or non-executable binary never gets this far: the pre-flight
  # `maintenance meta` above catches both. So reaching here means the platform is
  # right and the boot itself failed, which is the interesting case.
  report fail "the binary stays running" "it exited"
  diagnostics
  echo "# failures" >&2
  exit 1
fi

expect "GET / answers 200 without PHX_SERVER" 200 "$status"

# The page is the now playing LiveView, so the markup below is what the binary
# has to ship: the root layout with its digested assets, the LiveView itself,
# and the click handler that toggles play-pause.
for selector in 'data-phx-session' 'phx-click="toggle-play-pause"' '/assets/css/app-[^"]*\.css'; do
  if grep -qE "$selector" "$WORK/body"; then
    report ok "GET / renders $selector"
  else
    report fail "GET / renders $selector" "body: $(head -c 300 "$WORK/body" | tr '\n' ' ')"
  fi
done

# The digested manifest is what makes the CSS and JS load, and it only exists
# if `mix assets.deploy` ran before `mix release`.
for asset in /assets/css/app.css /assets/js/app.js; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT$asset")
  if [ "$code" = 200 ]; then
    report ok "GET $asset answers 200"
  else
    report fail "GET $asset answers 200" "actual: $code"
  fi
done

# The route index proves the router and the JSON layer work. The player routes
# are left out on purpose: they answer with the state of whatever player is on
# the network, and LSDP discovery takes a second or two after boot, so they are
# either slow or, on a machine without a player, empty.
code=$(curl -s -o "$WORK/api" -w '%{http_code}' "http://127.0.0.1:$PORT/api")
if [ "$code" = 200 ] && grep -q '/api/player-status-updates' "$WORK/api"; then
  report ok "GET /api answers 200"
else
  report fail "GET /api answers 200" "status: $code" "body: $(head -c 200 "$WORK/api" | tr '\n' ' ')"
fi

if grep -qE '\[error\]|\[warning\].*Address already in use' "$WORK/log"; then
  report fail "the log has no errors" "log: $(grep -E '\[error\]|\[warning\].*Address already in use' "$WORK/log" | head -3 | tr '\n' ' ')"
else
  report ok "the log has no errors"
fi

# The log has to be read before cleanup removes it.
if [ "$failures" -ne 0 ]; then
  diagnostics
fi

cleanup
trap - EXIT INT TERM

if [ "$failures" -eq 0 ]; then
  echo "# all good"
else
  echo "# failures" >&2
  exit 1
fi
