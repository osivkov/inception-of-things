#!/bin/sh
set -eu
image=${1:?Usage: smoke-container.sh IMAGE v1-or-v2 [HOST_PORT]}
version=${2:?Expected version required}
port=${3:-8888}
case "$version" in v1|v2) ;; *) echo 'Expected v1 or v2' >&2; exit 2;; esac
case "$port" in ''|*[!0-9]*) echo 'Port must be numeric' >&2; exit 2;; esac
for tool in docker curl python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool" >&2; exit 1; }
done
name="cup-smoke-$$"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || :; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker run -d --name "$name" --platform linux/amd64 --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=32m -p "127.0.0.1:$port:8888" "$image" >/dev/null
base="http://localhost:$port"
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS --max-time 2 "$base/healthz" >/dev/null 2>&1; then ready=1; break; fi
    sleep 1
done
if [ "$ready" -ne 1 ]; then docker logs "$name"; echo 'Container did not become ready' >&2; exit 1; fi
[ "$(curl -fsS "$base/healthz")" = ok ]
curl -fsS "$base/version.json" | python3 -c 'import json,sys; assert json.load(sys.stdin)["version"] == sys.argv[1]' "$version"
curl -fsS "$base/" | python3 -c 'import sys; assert "One more cup" in sys.stdin.read()'
[ "$(curl -sS -o /dev/null -w '%{http_code}' "$base/no-such-route")" = 404 ]
curl -fsSI "$base/timer.mjs" | python3 -c 'import sys; assert "application/javascript" in sys.stdin.read().lower()'
[ "$(docker exec "$name" id -u)" = 101 ]
echo "Passed: $image ($version), HTTP endpoints, module type, 404 and UID 101"
