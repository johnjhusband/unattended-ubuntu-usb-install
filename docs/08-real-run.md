# 8. The real run

## Before starting

1. **Refresh what the stick carries.** Memory files and conversations change
   until the last minute. Copy them again, then re-verify the stick against
   the build copies (docs/06, step 11). Confirm no sign-in token is on it:
   `find /mnt/stick -name '.credentials*'` prints nothing.
2. **Confirm the password hash on the stick is the current one.**
   ```bash
   H=$(sudo awk -F: '$1=="tara"{print $2}' /etc/shadow)
   grep -qF "$H" /mnt/stick/autoinstall.yaml && echo same
   ```
3. **Mains power.** `cat /sys/class/power_supply/AC*/online` → `1`.
4. **Download servers reachable right now.**
   ```bash
   curl -sIL -m 10 -o /dev/null -w '%{http_code}\n' http://us.archive.ubuntu.com/ubuntu/dists/stonking/InRelease
   curl -sIL -m 10 -o /dev/null -w '%{http_code}\n' https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
   ```
5. **Tell the firmware to boot the stick once.**
   ```bash
   sudo efibootmgr -C -d /dev/sdb -p 1 -L "BocaBell stick" -l '\EFI\boot\bootx64.efi'
   efibootmgr                      # note the new entry's number, e.g. Boot0001
   sudo efibootmgr -n 0001         # BootNext: that entry, next restart only
   ```
   `-C` creates the entry **without** adding it to the permanent boot order.
   `BootNext` applies to one restart. If the firmware ignores it, the
   machine simply boots the old system and nothing is lost.

Then restart the machine. From here nobody touches it.

## What happened

| Time | Event |
|---|---|
| ~01:13 | Restart. Firmware boots the stick through the one-time entry |
| 01:14:14 | `early.sh` starts: Claude Code into the live system, NetworkManager installed, Wi-Fi joined on the real card, internet confirmed |
| 01:15:05 | `early.sh` done (51 seconds) |
| 01:15:13 | Installer log: `NetworkManager is enabled … Not applying network settings.` `has_network True` |
| 01:15:28 | Partitioning starts: the point of no return |
| 01:16:44 | Base system copied from the stick |
| 01:20:54 – 01:22:59 | Installer's own final configuration (SSH server, Wi-Fi package, security updates) |
| 01:22:59 – 02:09:18 | `target-setup.sh`: desktop and software downloaded and installed, settings applied (46 minutes) |
| 02:09:18 | Installer reports `SUCCESS` and restarts the machine by itself |
| 02:09:36 | New system boots from the hard drive; cloud-init creates the user; first-boot script places Claude Code and its data |
| 02:11:27 | Automatic login; desktop |

55 minutes of install, about 2 minutes of first boot. The firmware's
one-time entry was gone afterwards and the boot order pointed at the new
system.

## Result, checked on the running system

| Item | Result |
|---|---|
| OS / desktop | Ubuntu 26.10, GNOME on Wayland |
| Installer | `SUCCESS`, 0 failed steps |
| Hostname / user / passwordless `sudo` | `BocaBell` / `tara` / yes |
| Disk | 1 GB EFI partition + 930.5 GB ext4 |
| Requested packages | 14 of 14 installed |
| Firefox, `unattended-upgrades`, welcome wizard, usage reporting, crash upload | absent |
| Dock | Chrome, Files, Terminal |
| Wi-Fi | connected with the carried profile |
| SSH | listening (socket-activated: `ssh.socket` enabled; `ssh.service` shows "disabled", which is normal) |
| Automatic login | yes |
| Claude Code | on the path, runs, not signed in at first boot |
| Memory files / conversations | all restored, owned by the user |
| Payload on disk | removed by the first-boot script |
| Ubuntu Pro services | masked |

## Deviations and leftovers

1. **`dmidecode` is installed** although it was on the "not wanted" list.
   `libparted` depends on it, and the desktop, the file manager and the
   updater depend on that. It was not in the VM checklist, so the tests did
   not flag it. Lesson: every "must be absent" item belongs in the
   checklist, and should be checked for removability *before* promising it.
2. **55 minutes, not 19.** The VM's virtual disk sat on a fast path; the
   laptop has a spinning drive. Quote real-hardware times only after
   measuring them.
3. **Two unrelated services failed once after boot**: `fwupd-refresh`
   (firmware update list download) and `geoclue` (location lookup, timed
   out). Nothing requested depends on them.
4. **Memory**: still 16 GB visible of 32 GB fitted. Hardware.
5. **The stick still holds the password hash and the Wi-Fi key.** Wipe it
   or store it accordingly.

## The risk that was accepted

The Wi-Fi card's firmware had stalled once on the old system that same
night (docs/02). Had it happened during the 46 minutes of `target-setup.sh`
while packages were still downloading, the install would have failed with
the disk already erased. A recovery loop
was proposed and declined. The run did not hit it. If you build this for a
machine you cannot easily retry on, add the recovery and test it by cutting
the simulated access point mid-download.

## If it had failed

- **Before the disk was touched** (no Wi-Fi, no internet): the installer
  stops with an error on screen. Restarting without the stick boots the old
  system, untouched.
- **After**: the stick is still a complete installer and can be started
  again. Its live system has a shell (press Enter at the error) with
  `claude` available, the restored conversations listed, and the installer's
  logs under `/var/log/installer/` and `/var/log/bocabell-early.log`.
- Either way: find the cause, fix it on the stick, verify the stick, run
  the whole install again from the start. No repairs in place.
