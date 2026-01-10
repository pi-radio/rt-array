#!/bin/sh
set -e

ts() { date '+[%Y-%m-%d %H:%M:%S]'; }

LOGDIR=/var/log
RFTOOL_PORTS="8081 8082"
PIRADIO_PORT=8083

mkdir -p "$LOGDIR"

# trd-autostart already ensures sdcard is mounted here
NETCFG=/run/media/mmcblk0p1/network.conf
IFACE=eth0

if [ -f "$NETCFG" ]; then
    echo "$(ts) Loading network config from $NETCFG"
    . "$NETCFG"
else
    echo "$(ts) No network.conf found, using existing network settings"
fi

# wait for network. This ensures the apps are launched after eth is up
echo "$(ts) Waiting for network..."
timeout=30
while [ $timeout -gt 0 ]; do
    if ip link show eth0 2>/dev/null | grep -q "state UP"; then
        echo "$(ts) Network interface is up"
        break
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "$(ts) WARNING: Network interface timeout, continuing anyway"
fi

if [ -n "$IPADDR" ]; then
    echo "$(ts) Configuring IP address on $IFACE"
    # set mac
    ip link set "$IFACE" down
    ip link set dev "$IFACE" address "$MACADDR"
    ip link set "$IFACE" up

    ip addr flush dev "$IFACE"
    ip addr add "$IPADDR/24" dev "$IFACE"
    ip link set "$IFACE" up

    if [ -n "$GATEWAY" ]; then
        ip route replace default via "$GATEWAY"
    fi

    echo "$(ts) IP configured: $IPADDR"
fi

echo "$(ts) Starting rftool"
rftool &
RFTOOL_PID=$!
sleep 5

# verify rftool is still running. A good safety check. 
# piradio app fails if fpga image is not loaded
if ! kill -0 $RFTOOL_PID 2>/dev/null; then
    echo "$(ts) ERROR: rftool died during startup" >&2
    exit 1
fi

# not strictly necessary, but saves lot of debugging time
for port in $RFTOOL_PORTS; do
    timeout=15
    while [ $timeout -gt 0 ]; do
        if netstat -tln | grep -q ":$port "; then
            echo "$(ts) rftool TCP server is listening on port $port"
            break
        fi
        sleep 1
        timeout=$((timeout - 1))
    done
    if [ $timeout -eq 0 ]; then
        echo "$(ts) WARNING: rftool port $port not detected, continuing anyway"
    fi
done

echo "$(ts) Starting piradio"
piradio &
PIRADIO_PID=$!
sleep 5

# Verify piradio is still running
if ! kill -0 $PIRADIO_PID 2>/dev/null; then
    echo "$(ts) ERROR: piradio failed to start" >&2
    exit 1
fi

# Wait for piradio TCP port
timeout=15
while [ $timeout -gt 0 ]; do
    if netstat -tln | grep -q ":$PIRADIO_PORT "; then
        echo "$(ts) piradio TCP server is listening on port $PIRADIO_PORT"
        break
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "$(ts) WARNING: piradio port $PIRADIO_PORT not detected"
fi

echo "$(ts) Autostart complete!"
echo "$(ts)   rftool:  PID=$RFTOOL_PID (ports 8081, 8082)"
echo "$(ts)   piradio: PID=$PIRADIO_PID (port 8083)"

exit 0