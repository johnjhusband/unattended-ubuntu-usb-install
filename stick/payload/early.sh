#!/bin/bash
# Runs in the installer's own Ubuntu (from the stick), before the disk is touched.
# A non-zero exit stops the install with the hard drive untouched.
set -uo pipefail
exec > >(tee -a /var/log/bocabell-early.log) 2>&1
P=/cdrom/payload

# --- A. Claude Code in this installer environment (for help if the install fails).
#        Never blocks the install.
(
    set -e
    if [ ! -x /usr/local/lib/bocabell/claude ]; then
        mkdir -p /usr/local/lib/bocabell
        xz -dc "$P/claude.xz" > /usr/local/lib/bocabell/claude.tmp
        chmod 755 /usr/local/lib/bocabell/claude.tmp
        mv /usr/local/lib/bocabell/claude.tmp /usr/local/lib/bocabell/claude
    fi
    # Always start from /root so the restored conversations are listed by --resume.
    printf '#!/bin/sh\ncd /root && exec /usr/local/lib/bocabell/claude "$@"\n' > /usr/local/bin/claude
    chmod 755 /usr/local/bin/claude
    mkdir -p /root/.claude
    cp -r "$P/claude/." /root/.claude/
    # Conversations are filed by the directory they ran in; make them visible from /root too.
    if [ -d /root/.claude/projects/-home-tara ] && [ ! -d /root/.claude/projects/-root ]; then
        cp -r /root/.claude/projects/-home-tara /root/.claude/projects/-root
    fi
    echo "early: Claude Code ready (type: claude)"
) || echo "early: WARNING: could not set up Claude Code here (install continues)"

# --- B. Internet. Required: the desktop and software are downloaded during the install.
set -e
# Online = any one of Ubuntu's download servers answers. Never depend on a single name.
online() {
    local u
    for u in http://us.archive.ubuntu.com/ubuntu/dists/ http://security.ubuntu.com/ubuntu/dists/ \
             http://archive.ubuntu.com/ubuntu/dists/ http://connectivity-check.ubuntu.com/; do
        curl -fsS -m 8 -o /dev/null "$u" 2>/dev/null && return 0
    done
    return 1
}
# wait_online N: try up to N times, 3 seconds apart.
wait_online() { local i; for i in $(seq 1 "$1"); do online && return 0; sleep 3; done; return 1; }
wifi_iface() { local n; for n in /sys/class/net/*; do [ -d "$n/wireless" ] && { basename "$n"; return 0; }; done; return 1; }

# A network that is already plugged in may still be starting; give it a moment.
if ! wait_online 4; then
    IFACE=""
    for i in $(seq 1 20); do
        IFACE=$(wifi_iface) && break
        sleep 1
    done
    if [ -n "$IFACE" ]; then
        echo "early: bringing up Wi-Fi on $IFACE"
        # NetworkManager runs the Wi-Fi link, using the same saved profile the installed
        # system uses. The installer leaves a NetworkManager-run connection alone; Wi-Fi set
        # up through netplan here would be switched off again by the installer's own
        # network step (it rewrites netplan from a snapshot taken before this script ran).
        dpkg -i "$P"/debs/*.deb
        install -m 600 "$P/wifi.nmconnection" /etc/NetworkManager/system-connections/wifi.nmconnection
        systemctl restart NetworkManager
        wait_online 60 || true
    else
        echo "early: no Wi-Fi adapter here; waiting for the wired network"
        wait_online 40 || true
    fi
fi
# Final verdict: no internet = stop here, hard drive untouched.
wait_online 3
echo "early: internet OK"
