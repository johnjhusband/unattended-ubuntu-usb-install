# 3. The final design

## In one paragraph

The USB stick **is** the installer: a trimmed copy of the Ubuntu Server 26.10
live installer, plus an answer file and a small payload. The stick's boot
menu starts the installer with no prompts. A script runs first, in the
installer's own live system: it installs Claude Code there (for rescue),
brings up Wi-Fi, and refuses to continue unless the internet is reachable.
The installer then erases the disk and installs a minimal Ubuntu Server. A
second script, run inside the new system before it ever boots, downloads the
desktop and all software and applies every setting. The installer reboots by
itself. On first boot a third script does the few things that need the user
account to exist, then deletes itself.

## The flow

```
power on
  └─ firmware boots the stick (one-time boot entry)
       └─ stick's GRUB menu, 3 s timeout
            ├─ if the hard drive already holds a finished install → boot that
            └─ else: installer kernel with `autoinstall noprompt`
                 └─ installer live system (runs from the stick, in RAM)
                      ├─ reads /cdrom/autoinstall.yaml
                      ├─ early-commands: payload/early.sh
                      │     A. Claude Code into the live system   (never blocks)
                      │     B. Wi-Fi up, internet check            (failure = STOP, disk untouched)
                      ├─ partitions and formats the largest disk   ← point of no return
                      ├─ installs minimal Ubuntu Server from the stick's image
                      ├─ late-commands:
                      │     copy payload to /target/opt/bocabell
                      │     chroot: payload/target-setup.sh        (desktop, software, settings)
                      │     touch /target/var/lib/bocabell-installed
                      └─ reboots by itself, no prompt
new system, first boot
  ├─ cloud-init creates the user `tara`
  ├─ bocabell-firstboot.service: payload/firstboot.sh  (Claude Code + data for tara)
  └─ GDM logs `tara` in automatically → desktop
```

## Decisions and their reasons

### The stick is the installer, not a side-car

Earlier designs kept the installer on a partition of the hard disk and used
the stick only for backups and a post-install script. That fails
requirement P6: the installer erases its own home, so a failure halfway
leaves nothing bootable. With the installer on the stick, a failed install
can simply be started again, and the stick's live system is a working Linux
to diagnose from.

### Ubuntu Server image, trimmed, on a 1.9 GB stick

| Part of the Server ISO | Size | On the stick? |
|---|---|---|
| `casper/` (kernel, initrd, the live system and install images) | 1,605 MB | yes |
| `pool/` (offline package store) | 1,139 MB | **no** |
| `EFI/`, `boot/`, `.disk/`, `dists/`, `md5sum.txt` | ~16 MB | yes |
| Payload (Claude Code compressed, 7 `.deb` files, scripts, Claude data) | ~132 MB | added |

Dropping `pool/` is what makes it fit. Consequences, all handled:

- The installer lists the stick as a package source (`file:/cdrom`), but its
  files are missing. `apt` falls back to the network for each package. This
  was tested before relying on it (docs/04).
- The installer's own helper that installs `wpasupplicant` into the live
  system takes it from `pool/`. So the stick carries those packages itself
  and `early.sh` installs them first; the helper then finds the package
  "already installed".
- There is no offline fallback. So the answer file says
  `apt: fallback: abort`, and `early.sh` proves the internet is reachable
  before anything is erased.

The image is copied as plain files onto a single FAT32 partition flagged as
an EFI System Partition. No ISO remastering, no `dd`. UEFI firmware boots
`\EFI\boot\bootx64.efi` from it directly, and the files stay editable.

### Desktop on top of Server, not the Desktop image

The Desktop image is 6.6 GB and cannot be trimmed to 1.9 GB. Instead the
installer lays down `ubuntu-server-minimal`, and `target-setup.sh` installs
`ubuntu-desktop-minimal` from the network. This also means Firefox, the
welcome wizard and the reporting tools are never installed in the first
place (an `apt` pin at priority -1 guarantees it), instead of being removed
afterwards.

Two things then need converting from "server" to "desktop" behaviour, both
in `target-setup.sh`:

- Networking is handed from `systemd-networkd` to NetworkManager: the
  installer's netplan files are replaced with a one-line
  `renderer: NetworkManager`, and cloud-init's network handling is disabled.
- The default boot target is set to `graphical.target`.

### Three scripts, because three moments differ

| Script | Runs where and when | Why it cannot be merged with the others |
|---|---|---|
| `early.sh` | Installer's live system, before partitioning | The only place a failure costs nothing |
| `target-setup.sh` | Inside the new system (`curtin in-target`), before first boot | Needs the new system's package manager; the user account does not exist yet |
| `firstboot.sh` | New system, first boot, before the display manager | The user is created by cloud-init on first boot, so anything in the user's home must wait until then |

`firstboot.sh` needs no network. It is ordered
`After=cloud-config.service` and
`Before=display-manager.service gdm.service`, so the desktop does not appear
until Claude Code and its data are in place.

### Every step that can fail, fails loudly and early

- `early.sh` part B runs under `set -e`. No internet → non-zero exit → the
  installer stops with the disk untouched.
- `target-setup.sh` runs under `set -euo pipefail` and re-reads what it
  wrote (the `sudo` rule is checked with `visudo`, the auto-login lines are
  `grep`ped back).
- The marker `/var/lib/bocabell-installed` is the **last** late-command. It
  exists only if everything before it succeeded.
- `firstboot.sh` ends by running `claude --version` as the user.

### No prompts, anywhere

| Prompt | What removes it |
|---|---|
| "Continue with autoinstall? (yes/no)" | kernel parameter `autoinstall` |
| Any installer screen | a complete answer file with no `interactive-sections` |
| "Please remove the installation medium, then press ENTER" | kernel parameter `noprompt`, plus `shutdown: reboot` |
| GNOME's welcome wizard | `gnome-initial-setup` pinned so it is never installed |
| Login screen | GDM `AutomaticLoginEnable=true`, `AutomaticLogin=tara` |
| Package configuration dialogs | `DEBIAN_FRONTEND=noninteractive`, `NEEDRESTART_MODE=a` |

### The stick can stay in

After a successful install the stick's boot menu first looks for
`/var/lib/bocabell-installed` on any disk. If found, the default entry boots
the installed system (by loading that system's own GRUB menu with
`configfile`) instead of reinstalling. So leaving the stick plugged in, or
the firmware preferring USB, cannot trigger a second erase.

### Claude Code: placed, not "installed"

Claude Code's own `claude install` command needs the internet even when it
is handed a local copy of the program (tested in a network-less sandbox).
So `firstboot.sh` puts the program directly where a native install would:

```
~/.local/share/claude/versions/<version>     the program (decompressed from claude.xz)
~/.local/bin/claude                          symlink to it
~/.claude.json                               {"installMethod":"native","autoUpdates":false,"autoUpdatesProtectedForNative":true}
~/.claude/                                   settings.json, projects/<dir>/memory, conversations
```

and `target-setup.sh` adds `~/.local/bin` to the path via `/etc/skel/.bashrc`
(so the user created later inherits it). `firstboot.sh` adds the line again
if it is somehow missing.

In the installer's live system the same program is unpacked to
`/usr/local/lib/bocabell/claude` with a wrapper at `/usr/local/bin/claude`
that starts in `/root`. Conversations are filed by working directory, so the
restored `projects/-home-tara` folder is also copied to `projects/-root`;
otherwise `claude --resume` would list nothing there.

### Wi-Fi in the installer is run by NetworkManager

This is the least obvious decision and the most important one. It is
explained in full in docs/05. In short: if the installer's live system joins
Wi-Fi through netplan (its native tool), the installer itself switches Wi-Fi
off again a few seconds later, carries on, erases the disk, and then fails.
If NetworkManager owns the link, the installer leaves it alone.
