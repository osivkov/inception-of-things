#!/usr/bin/env bash
set -uo pipefail
RUNS="${1:-10}"; OK=0; FAIL=0
mkdir -p /tmp/iot-stress
for i in $(seq 1 "$RUNS"); do
  echo "=== RUN $i/$RUNS $(date +%T) ==="
  make destroy >/dev/null 2>&1
  start=$(date +%s)
  if make up >"/tmp/iot-stress/run-$i.log" 2>&1; then
    OK=$((OK+1)); echo "PASS ($(( $(date +%s)-start ))s)"
  else
    FAIL=$((FAIL+1)); echo "FAIL, см. /tmp/iot-stress/run-$i.log"
  fi
  free -h | sed -n 2p
done
make destroy >/dev/null 2>&1
echo "OK=$OK FAIL=$FAIL"