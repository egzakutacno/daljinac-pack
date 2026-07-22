#!/bin/bash
# Daljinac SSH port forward - RPi → VPS
# Koristi se preko systemd servisa (daljinac-fwd.service)
# Auto-restart, keepalive, start na boot.

ADMIN_KEY="$HOME/.ssh/daljinac_admin"
VPS="root@31.220.74.109"

# Automatski forward svih portova u opsegu.
# Novi agenti — samo se dodaju u registerd daemon na VPS-u, RPi ne treba mijenjati.
V1_RANGE=$(seq 7081 7100)
V2_RANGE=$(seq 7181 7200)

ARGS=()
for p in $V1_RANGE $V2_RANGE; do
    ARGS+=(-L "$p:127.0.0.1:$p")
done

exec ssh -i "$ADMIN_KEY" \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ExitOnForwardFailure=no \
    -N \
    "${ARGS[@]}" \
    "$VPS"
