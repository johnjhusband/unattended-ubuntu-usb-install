#!/bin/bash
# Checklist run against an installed system's root filesystem mounted at $1
# (a VM disk attached with qemu-nbd, mounted read-only), after its first boot.
# These are the checks used to accept a test run. Needs sudo.
R=${1:?usage: checklist.sh /mnt/installed-root}
echo "hostname: $(sudo cat $R/etc/hostname) | user tara: $(grep -c '^tara:' $R/etc/passwd) | sudo rule: $(sudo cat $R/etc/sudoers.d/tara)"
want="ubuntu-desktop-minimal openssh-server git tmux jq unzip build-essential python3-venv python3-pip nodejs npm curl google-chrome-stable network-manager"
n=0; for p in $want; do sudo chroot $R dpkg-query -W -f='${Status}\n' $p 2>/dev/null | grep -q '^install ok installed' && n=$((n+1)) || echo "MISSING: $p"; done; echo "installed as required: $n of 14"
a=0; for p in firefox unattended-upgrades gnome-initial-setup ubuntu-report whoopsie; do sudo chroot $R dpkg-query -W -f='${Status}\n' $p 2>/dev/null | grep -q '^install ok installed' && echo "PRESENT: $p" || a=$((a+1)); done; echo "absent as required: $a of 5 | firefox snap files: $(sudo sh -c "ls $R/var/lib/snapd/snaps 2>/dev/null | grep -ci firefox")"
echo "auto-login: $(sudo grep -E '^AutomaticLogin' $R/etc/gdm3/custom.conf | tr '\n' ' ') | default: $(readlink $R/etc/systemd/system/default.target | xargs basename)"
echo "dock: $(sudo grep favorite $R/etc/dconf/db/local.d/00-bocabell-dock)"
echo "network: $(sudo grep renderer $R/etc/netplan/*.yaml | tr -s ' ') | netplan files: $(sudo ls $R/etc/netplan | tr '\n' ' ') | wifi profile: $(sudo ls -l $R/etc/NetworkManager/system-connections/ | awk 'NR>1{print $1,$3,$9}')"
echo "claude: $(readlink $R/home/tara/.local/bin/claude) | size $(sudo stat -c %s $R/home/tara/.local/share/claude/versions/*) | owner $(sudo stat -c %U $R/home/tara/.local/share/claude/versions/*) | path line in .bashrc: $(grep -c '.local/bin' $R/home/tara/.bashrc)"
echo "claude data: memories $(sudo sh -c "ls $R/home/tara/.claude/projects/-home-tara/memory | wc -l"), conversations $(sudo sh -c "ls $R/home/tara/.claude/projects/-home-tara/*.jsonl | wc -l"), sign-in token files $(sudo sh -c "find $R/home/tara -name '.credentials.json' | wc -l"), owner $(sudo stat -c %U $R/home/tara/.claude)"
echo "first boot: $(sudo tail -1 $R/var/log/bocabell-firstboot.log) | markers: $(sudo sh -c "ls $R/var/lib/bocabell-installed $R/var/lib/bocabell-firstboot.done 2>/dev/null | wc -l") | leftover payload: $(sudo sh -c "ls $R/opt/bocabell 2>/dev/null | wc -l")"
m=0; for u in ubuntu-advantage.service ua-timer.timer esm-cache.service apt-news.service; do [ "$(readlink $R/etc/systemd/system/$u)" = /dev/null ] && m=$((m+1)); done; echo "pro services masked: $m of 4"
echo "curtin failed steps: $(sudo grep -c 'finish:.*FAIL' $R/var/log/installer/curtin-install.log)"
echo "target-setup reached end: $(sudo grep -c '== target setup done' $R/var/log/installer/installer-journal.txt)"
echo "installer network decision:"; sudo grep -n "NetworkManager is enabled\|has_network\|Skipping mirror" $R/var/log/installer/subiquity-server-debug.log | cut -c1-170
