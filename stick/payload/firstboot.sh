#!/bin/bash
# Runs once on the first boot of the new system, before the desktop appears.
# Does the steps that need the user account to exist. Needs no network.
set -euo pipefail
exec > >(tee -a /var/log/bocabell-firstboot.log) 2>&1
P=/opt/bocabell

echo "== wait for user tara"
for i in $(seq 1 180); do id tara >/dev/null 2>&1 && [ -d /home/tara ] && break; sleep 1; done
id tara
test -d /home/tara

echo "== Claude Code settings, memory, conversations"
install -d -o tara -g tara /home/tara/.claude
cp -r "$P/claude/." /home/tara/.claude/
chown -R tara:tara /home/tara/.claude

echo "== Claude Code (installed, not logged in)"
# Placed directly from the stick, in the same layout Claude Code's own native
# install uses (its installer needs the internet even for a bundled copy).
VER=$(cat "$P/claude.version")
install -d -o tara -g tara /home/tara/.local /home/tara/.local/bin /home/tara/.local/share \
    /home/tara/.local/share/claude /home/tara/.local/share/claude/versions
xz -dc "$P/claude.xz" > "/home/tara/.local/share/claude/versions/$VER"
chmod 755 "/home/tara/.local/share/claude/versions/$VER"
ln -sfn "/home/tara/.local/share/claude/versions/$VER" /home/tara/.local/bin/claude
if [ ! -e /home/tara/.claude.json ]; then
    printf '{\n  "installMethod": "native",\n  "autoUpdates": false,\n  "autoUpdatesProtectedForNative": true\n}\n' > /home/tara/.claude.json
fi
chown -R tara:tara /home/tara/.local /home/tara/.claude.json
test -x /home/tara/.local/bin/claude
sudo -u tara -H /home/tara/.local/bin/claude --version
grep -q '.local/bin' /home/tara/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/tara/.bashrc
chown tara:tara /home/tara/.bashrc

echo "== finish"
touch /var/lib/bocabell-firstboot.done
systemctl disable bocabell-firstboot.service
rm -rf "$P"
echo "== first boot done"
