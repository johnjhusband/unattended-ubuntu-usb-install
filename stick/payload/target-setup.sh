#!/bin/bash
# Runs once inside the newly installed system at the end of the install,
# before its first boot. The user account does not exist yet (created on first boot).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
P=/opt/bocabell

echo "== passwordless sudo"
echo 'tara ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/tara
chmod 440 /etc/sudoers.d/tara
visudo -c -f /etc/sudoers.d/tara

echo "== never install: Firefox, welcome wizard, usage reporting, crash upload"
cat > /etc/apt/preferences.d/bocabell-never <<'EOF'
Package: firefox gnome-initial-setup ubuntu-insights ubuntu-report whoopsie
Pin: release *
Pin-Priority: -1
EOF

echo "== desktop and tools"
apt-get update
apt-get install -y ubuntu-desktop-minimal \
    openssh-server git tmux jq unzip build-essential python3-venv python3-pip nodejs npm curl

echo "== remove unattended-upgrades"
apt-get purge -y unattended-upgrades

echo "== Chrome"
curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y /tmp/chrome.deb
rm -f /tmp/chrome.deb

echo "== boot to the desktop, automatic login"
systemctl set-default graphical.target
python3 - <<'EOF'
import configparser
p = "/etc/gdm3/custom.conf"
c = configparser.ConfigParser()
c.optionxform = str
c.read(p)
if not c.has_section("daemon"):
    c.add_section("daemon")
c.set("daemon", "AutomaticLoginEnable", "true")
c.set("daemon", "AutomaticLogin", "tara")
with open(p, "w") as f:
    c.write(f, space_around_delimiters=False)
EOF
grep -q '^AutomaticLoginEnable=true' /etc/gdm3/custom.conf
grep -q '^AutomaticLogin=tara' /etc/gdm3/custom.conf

echo "== dock"
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
cat > /etc/dconf/db/local.d/00-bocabell-dock <<'EOF'
[org/gnome/shell]
favorite-apps=['google-chrome.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Ptyxis.desktop']
EOF
dconf update

echo "== network: desktop-style (NetworkManager), with the saved Wi-Fi profile"
rm -f /etc/netplan/*.yaml
cat > /etc/netplan/01-network-manager-all.yaml <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
chmod 600 /etc/netplan/01-network-manager-all.yaml
rm -f /etc/cloud/cloud.cfg.d/90-installer-network.cfg
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-bocabell-disable-network-config.cfg
install -m 600 "$P/wifi.nmconnection" /etc/NetworkManager/system-connections/wifi.nmconnection
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

echo "== Claude Code on the path in every terminal"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> /etc/skel/.bashrc

echo "== Ubuntu Pro: switch off its services and prompts"
systemctl mask ubuntu-advantage.service ua-timer.timer ua-timer.service ua-reboot-cmds.service esm-cache.service apt-news.service ubuntu-advantage-desktop-daemon.service
rm -f /etc/apt/apt.conf.d/20apt-esm-hook.conf

echo "== first-boot step"
install -m 755 "$P/firstboot.sh" /usr/local/sbin/bocabell-firstboot
install -m 644 "$P/bocabell-firstboot.service" /etc/systemd/system/bocabell-firstboot.service
systemctl enable bocabell-firstboot.service

echo "== target setup done"
