#!/usr/bin/env bash
set -euo pipefail

LAB_TOPO="/home/speed/Dev/.openclaw/workspace/ring6-iol/ring6-iol.clab.yml"
R1_HOST="clab-ring6-iol-r1"
R1_PASS="admin"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }
}

need_cmd containerlab
need_cmd docker
need_cmd sshpass

log "Checking lab status"
containerlab inspect -t "$LAB_TOPO" >/dev/null

log "Checking r1 IS-IS neighbors"
ISIS_OUT=$(printf 'terminal length 0\nshow isis neighbors\n' | \
  sshpass -p "$R1_PASS" ssh -tt \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$R1_HOST" 2>/dev/null || true)

echo "$ISIS_OUT" | grep -q 'r2\s\+L2' || { echo "FAIL: r2 IS-IS adjacency not UP on r1"; exit 1; }
echo "$ISIS_OUT" | grep -q 'r6\s\+L2' || { echo "FAIL: r6 IS-IS adjacency not UP on r1"; exit 1; }

log "Checking r1 BGP neighbors (all established)"
BGP_OUT=$(printf 'terminal length 0\nshow ip bgp summary\n' | \
  sshpass -p "$R1_PASS" ssh -tt \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$R1_HOST" 2>/dev/null || true)

for n in 2.2.2.2 3.3.3.3 4.4.4.4 5.5.5.5 6.6.6.6; do
  echo "$BGP_OUT" | grep -E "^$n\s+4\s+65000" >/dev/null || { echo "FAIL: Missing BGP neighbor $n on r1"; exit 1; }
done

if echo "$BGP_OUT" | grep -E '(^|\s)(Active|Idle|Connect|OpenSent|OpenConfirm)(\s|$)' >/dev/null; then
  echo "FAIL: One or more BGP neighbors not established"
  echo "$BGP_OUT"
  exit 1
fi

log "Checking end-to-end host pings"
docker exec clab-ring6-iol-h1 ping -c 3 10.4.4.10 >/dev/null
docker exec clab-ring6-iol-h2 ping -c 3 10.1.1.10 >/dev/null

log "PASS: ring6-iol validation successful"
