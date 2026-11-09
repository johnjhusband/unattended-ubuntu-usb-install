#!/bin/bash
# TEST ONLY: first late-command. Saves installer-side evidence onto the new disk,
# because the live system's own logs vanish at reboot.
O=/target/var/log/bocabell-test; mkdir -p $O
cp /var/log/test-ap.log /var/log/bocabell-early.log $O/ 2>/dev/null
{ date; echo "== nmcli networking"; nmcli networking; echo "== nmcli dev"; nmcli -t dev; echo "== routes"; ip route; echo "== netplan dir"; ls -la /etc/netplan; echo "== wpa units"; systemctl list-units --no-legend 'netplan-wpa*' 'NetworkManager*' 'wpa_supplicant*'; echo "== nm journal"; journalctl -u NetworkManager --no-pager | tail -60; } > $O/state-at-late.txt 2>&1
true
