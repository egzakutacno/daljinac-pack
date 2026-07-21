#!/bin/bash
# Daljinac SSH port forward - RPi → VPS
# Koristi se preko systemd servisa (daljinac-fwd.service)
# Auto-restart, keepalive, start na boot.

ADMIN_KEY="$HOME/.ssh/daljinac_admin"
VPS="root@31.220.74.109"

# Lijevo: lokalni portovi koje forwardujemo
# Desno: VPS portovi (gdje su agent tuneli)
V1_PORTS="7081 7082 7084"
V2_PORTS="7182 7184 7185"

ARGS=()
for p in $V1_PORTS $V2_PORTS; do
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
