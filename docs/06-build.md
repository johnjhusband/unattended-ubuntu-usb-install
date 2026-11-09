# 6. Build the stick

These are the steps as they were actually run, on the laptop itself while it
was still running the old system. Paths are examples. `/dev/sdb` is the
stick here; **confirm which device is the stick on your machine before any
command that writes to it.**

Work somewhere that is not the stick, for example `~/install-build`. (That
directory is on the disk that will be erased. This is fine: by the time the
install starts, everything needed is on the stick. It does mean the build
files are gone afterwards.)

## 1. Get and verify the installer image

```bash
cd ~/install-build
curl -sSL -C - -O https://releases.ubuntu.com/26.10/ubuntu-26.10-live-server-amd64.iso
curl -sSL -O https://releases.ubuntu.com/26.10/SHA256SUMS
sha256sum -c --ignore-missing SHA256SUMS
```

## 2. Mount it and measure it

```bash
sudo mkdir -p /mnt/srv /mnt/srvmin /mnt/srvstd /mnt/srvinst /mnt/srvsnap
sudo mount -o loop,ro ubuntu-26.10-live-server-amd64.iso /mnt/srv
cd /mnt/srv && du -sm * .disk | sort -n
```

Expect roughly: `casper` 1,605 MB, `pool` 1,139 MB, everything else small.
If `casper` plus your payload does not fit your stick, stop here.

Mount the layers too; later steps read them (see docs/05 for the commands).

## 3. Confirm the image supports your Wi-Fi card

See docs/02. Driver module and firmware must be in `/mnt/srvmin`.

## 4. Confirm `apt` falls back to the network when `pool/` is missing

This is the assumption the trimmed stick rests on. Test it in a throwaway
`apt` configuration: one local `file://` source that has the image's
`dists/` but no `pool/`, plus the network archive.

```bash
T=$(mktemp -d); mkdir -p $T/lists/partial $T/cache/archives/partial $T/trim
cp -a /mnt/srv/dists $T/trim/
CN=$(. /etc/os-release; echo $VERSION_CODENAME)      # or read it from /mnt/srv/dists
printf 'deb [trusted=yes check-date=no] file://%s/trim %s main restricted\ndeb http://archive.ubuntu.com/ubuntu %s main restricted\n' $T $CN $CN > $T/sources.list
O="-o Dir::Etc::sourcelist=$T/sources.list -o Dir::Etc::sourceparts=/dev/null -o Dir::State::lists=$T/lists -o Dir::Cache=$T/cache -o Debug::NoLocking=1"
apt-get $O update
apt-get $O install -d --reinstall -y efibootmgr      # must end with the .deb downloaded
ls $T/cache/archives/*.deb
```

## 5. Write the answer file, boot menu and scripts

Start from the files under `stick/` in this repository. Change at least:

| File | What to change |
|---|---|
| `autoinstall.yaml` | `identity` (name, user, hostname), `timezone`, `locale`, `keyboard` |
| `payload/target-setup.sh` | the user name in the `sudo` rule and auto-login, the package list, the "never install" list, the dock |
| `payload/firstboot.sh` | the user name and home path |
| `payload/early.sh` | the `projects/-home-<user>` folder name if you carry Claude data |
| `payload/wifi.nmconnection` | create from the `.example`; `chmod 600` |

On a machine already connected to the Wi-Fi network through NetworkManager,
the profile can be taken from the running system instead of typed
(`sudo cat` the file under `/etc/NetworkManager/system-connections/` or, on
Ubuntu, `/run/NetworkManager/system-connections/`), keeping only the keys in
the example. Do not put `interface-name` or a MAC address in it; the same
file must work in the installer and in the installed system.

Check syntax:

```bash
for f in payload/early.sh payload/target-setup.sh payload/firstboot.sh; do bash -n $f; done
systemd-analyze verify payload/bocabell-firstboot.service
grub-script-check boot/grub/grub.cfg
```

## 6. Fill in the password hash

The hash comes straight from the running system, so the password is never
typed or shown. Keep the result out of version control and readable only by
you.

```bash
H=$(sudo awk -F: '$1=="tara"{print $2}' /etc/shadow); [ -n "$H" ]
sed "s|@@PWHASH@@|$H|" autoinstall.yaml > autoinstall.final.yaml
chmod 600 autoinstall.final.yaml
```

For a machine with no existing account, generate one with
`mkpasswd -m sha-512`.

## 7. Validate the answer file with the installer's own validator

The installer ships a validator script,
`scripts/validate-autoinstall-user-data.py`, and a JSON schema. Here it was
run from the copy inside the Ubuntu **Desktop** image's installer snap
(`ubuntu-desktop-bootstrap`), pointed at the **Server** image's list of
install sources so that `source: id: ubuntu-server-minimal` is recognised:

```bash
S=/mnt/snap      # the mounted installer snap that contains bin/subiquity/scripts/
cat > run.py <<EOF
import sys, runpy
sys.path.insert(0, "$S/bin/subiquity")
import subiquity.server.controllers.source as s
s.SOURCES_DEFAULT_PATH = "/mnt/srv/casper/install-sources.yaml"
sys.argv = ["validate", "-vv", "--json-schema", "$S/bin/subiquity/autoinstall-schema.json", "a.yaml"]
runpy.run_path("$S/bin/subiquity/scripts/validate-autoinstall-user-data.py", run_name="__main__")
EOF
ln -s $S/bin/subiquity/examples examples      # the validator expects its example data here
cp autoinstall.final.yaml a.yaml
env SNAP=$S SUBIQUITY_ROOT=$S/bin/subiquity \
  PYTHONPATH=$S/bin/subiquity:$S/usr/lib/python3/site-packages:$S/usr/lib/python3/dist-packages:$S/lib/python3.12/site-packages \
  PATH=$S/bin:$S/sbin:$PATH $S/usr/bin/python3.12 run.py
rm -f a.yaml
```

Without the `SOURCES_DEFAULT_PATH` line the validator rejects the `source`
section, because it compares against a different image's source list. Run it
from a writable directory. Look for the same script inside the Server
image's own `subiquity` snap first; the paths differ between the two snaps.

## 8. Assemble the payload

**Wi-Fi packages.** The live system needs NetworkManager and
`wpasupplicant`. To get exactly the packages it lacks, and no version
mismatches, resolve them inside a scratch copy of the live system:

```bash
W=~/install-build/ovl; sudo mkdir -p $W/up $W/wk $W/m
sudo mount -t overlay overlay \
  -o lowerdir=/mnt/srvinst:/mnt/srvstd:/mnt/srvmin,upperdir=$W/up,workdir=$W/wk $W/m
sudo mount -t proc proc $W/m/proc
sudo sh -c "cat /etc/resolv.conf > $W/m/etc/resolv.conf"
sudo rm -f $W/m/etc/apt/sources.list.d/cdrom.sources
# Release pocket only, so nothing in the live system has to be upgraded:
sudo tee $W/m/etc/apt/sources.list.d/ubuntu.sources >/dev/null <<EOF
Types: deb
URIs: http://us.archive.ubuntu.com/ubuntu
Suites: stonking
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
sudo chroot $W/m apt-get update
sudo chroot $W/m apt-get install -y --no-install-recommends --download-only \
     network-manager wpasupplicant wireless-regdb
ls $W/m/var/cache/apt/archives/*.deb          # this is the set to carry
```

For 26.10 the set was seven files (about 4.6 MB): `network-manager`,
`libnm0`, `libndp0`, `libbluetooth3`, `wpasupplicant`, `libpcsclite1`,
`wireless-regdb`. Copy them to `payload/debs/`.

Then prove they install offline, in the same scratch copy:

```bash
sudo mkdir -p $W/m/tmp/nm && sudo cp payload/debs/*.deb $W/m/tmp/nm/
sudo chroot $W/m sh -c 'DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/nm/*.deb'   # must exit 0
```

(Messages about not being able to reach systemd or NetworkManager are
expected inside a chroot.)

**Claude Code.**

```bash
xz -6 -T0 -c "$(readlink -f ~/.local/bin/claude)" > payload/claude.xz
xz -t payload/claude.xz
claude --version | awk '{print $1}' > payload/claude.version
```

**Claude data**, without the sign-in token:

```bash
mkdir -p payload/claude/projects
cp ~/.claude/settings.json payload/claude/
cp -r ~/.claude/projects/-home-tara payload/claude/projects/
find payload -name '.credentials*'            # must print nothing
```

## 9. Partition and format the stick

**This erases the stick.**

```bash
sudo umount /dev/sdb* 2>/dev/null
sudo parted -s /dev/sdb mklabel gpt mkpart BOCABELL fat32 1MiB 100% set 1 esp on
sudo partprobe /dev/sdb
sudo mkfs.vfat -F 32 -n BOCABELL /dev/sdb1
sudo mkdir -p /mnt/stick && sudo mount -o uid=1000,gid=1000 /dev/sdb1 /mnt/stick
```

One GPT partition, FAT32, flagged as an EFI System Partition. The largest
file (the 1.38 GB squashfs) is under FAT32's 4 GB limit.

## 10. Copy the trimmed installer and your files

```bash
D=/mnt/stick; cd /mnt/srv
for d in casper EFI boot .disk md5sum.txt dists; do cp -r --no-preserve=all "$d" $D/; done   # everything except pool
cp ~/install-build/stick/boot/grub/grub.cfg   $D/boot/grub/grub.cfg       # replaces the image's menu
cp ~/install-build/stick/autoinstall.final.yaml $D/autoinstall.yaml
cp -r ~/install-build/stick/payload           $D/payload
sync
```

The image's GRUB finds its menu at `/boot/grub/grub.cfg` on the partition it
was started from, so replacing that one file is enough.

## 11. Verify the stick

Re-read every installer file from the stick and compare with Ubuntu's own
checksum list; then compare your files with the build copies.

```bash
sudo umount /mnt/stick && sudo mount -o ro,uid=1000,gid=1000 /dev/sdb1 /mnt/stick
cd /mnt/stick
grep -E '\./(casper|EFI|boot|\.disk)/' md5sum.txt | grep -v 'boot/grub/grub.cfg' > /tmp/stick.md5
md5sum -c --quiet /tmp/stick.md5            # no output = all files match (638 files here)
diff -rq ~/install-build/stick/payload /mnt/stick/payload
cmp ~/install-build/stick/autoinstall.final.yaml /mnt/stick/autoinstall.yaml
cmp ~/install-build/stick/boot/grub/grub.cfg /mnt/stick/boot/grub/grub.cfg
```

Repeat the last three comparisons after **every** later change to the
stick. A fix that exists only in the build directory is not a fix.

## 12. Test

Do not skip to the real machine. docs/07.
