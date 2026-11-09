#!/bin/bash
# TEST ONLY - never put this on the real stick.
# Runs inside the installer's live system in a VM, as the first early-command.
# Creates a simulated Wi-Fi card + access point (mac80211_hwsim + hostapd + dnsmasq)
# and hides the VM's wired NIC in a separate network namespace, so the install
# has to run over Wi-Fi exactly as it will on a laptop with no Ethernet.
set -euxo pipefail
exec > >(tee -a /var/log/test-ap.log) 2>&1
T=/cdrom/test
dpkg -i $T/debs/*.deb          # hostapd, dnsmasq-base, iw (not in the live system)
modprobe mac80211_hwsim radios=2
for i in $(seq 1 40); do
    mapfile -t W < <(for n in /sys/class/net/*; do [ -d "$n/wireless" ] && basename "$n"; done | sort)
    [ "${#W[@]}" -ge 2 ] && break; sleep 0.5
done
AP=${W[1]}                      # W[0] stays in the main namespace as the "laptop's Wi-Fi card"
PHY=$(cat /sys/class/net/$AP/phy80211/name)
ETH=""; for n in /sys/class/net/*; do b=$(basename "$n"); case $b in en*|eth*) ETH=$b; break;; esac; done
[ -n "$ETH" ]
ip netns add ap
iw phy "$PHY" set netns name ap
ip link set "$ETH" netns ap
N="ip netns exec ap"
$N ip link set lo up
# QEMU user-mode networking: guest 10.0.2.15, gateway 10.0.2.2, DNS 10.0.2.3
$N ip addr add 10.0.2.15/24 dev "$ETH"
$N ip link set "$ETH" up
$N ip route add default via 10.0.2.2
$N ip addr add 192.168.77.1/24 dev "$AP"
$N sysctl -w net.ipv4.ip_forward=1
$N nft -f - <<NFT
table ip testnat {
    chain post {
        type nat hook postrouting priority 100;
        oifname "$ETH" masquerade
    }
}
NFT
# Same SSID and key as the real profile, so the real early.sh is exercised unchanged.
SSID=$(sed -n 's/^ssid=//p' /cdrom/payload/wifi.nmconnection | head -1)
PSK=$(sed -n 's/^psk=//p' /cdrom/payload/wifi.nmconnection | head -1)
umask 077
cat > /run/test-hostapd.conf <<CONF
interface=$AP
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=$PSK
CONF
umask 022
# Own systemd units: processes started directly from an early-command do not
# reliably outlive it.
systemd-run --unit=test-hostapd ip netns exec ap hostapd /run/test-hostapd.conf
systemd-run --unit=test-dnsmasq ip netns exec ap dnsmasq --keep-in-foreground --conf-file=/dev/null \
    --interface="$AP" --bind-interfaces --dhcp-range=192.168.77.10,192.168.77.50,12h \
    --no-resolv --server=10.0.2.3 --dhcp-leasefile=/run/test-dnsmasq.leases
sleep 3
systemctl is-active test-hostapd test-dnsmasq
$N curl -fsS -m 10 -o /dev/null http://us.archive.ubuntu.com/ubuntu/dists/ && echo "test-ap: access point side has internet"
echo "test-ap: station=${W[0]} ap=$AP eth=$ETH ready"
