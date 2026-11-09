# Unattended Ubuntu desktop install from a 2 GB USB stick, over Wi-Fi

This repository records how one laptop was reinstalled with **zero questions,
zero manual steps, and a working desktop at the end**, and everything that
went wrong on the way. It is written so that another AI agent (or a person)
can repeat the result without repeating the failures.

The final run, on real hardware:

- Booted a 1.9 GB USB stick holding a trimmed Ubuntu Server 26.10 installer.
- Joined Wi-Fi by itself, checked for internet **before touching the disk**.
- Erased the 1 TB hard drive, installed Ubuntu, downloaded the GNOME desktop
  and all requested software, applied every setting.
- Rebooted by itself into an auto-logged-in desktop with Claude Code
  installed, on the path, and its settings, memory and conversations restored.
- Nobody typed anything. Elapsed time: 55 minutes on a spinning hard drive
  (19 minutes in a VM).

It took five designs and four VM test runs to get there. Two earlier real
installs failed. The most dangerous defect was found only by reading the
installer's source code, after a VM test had already passed.

## Read in this order

| File | What it gives you |
|---|---|
| [docs/01-goals.md](docs/01-goals.md) | The requirements, including the ones that were only discovered by failing them |
| [docs/02-hardware.md](docs/02-hardware.md) | The machine, the stick, and the constraints they impose |
| [docs/03-design.md](docs/03-design.md) | The final design and the reason for every part of it |
| [docs/04-history.md](docs/04-history.md) | Every attempt in order: what was tried, what failed, the root cause |
| [docs/05-installer-internals.md](docs/05-installer-internals.md) | How Ubuntu's installer (subiquity) really behaves; the facts the design depends on |
| [docs/06-build.md](docs/06-build.md) | Step-by-step: build the stick |
| [docs/07-testing.md](docs/07-testing.md) | How to test it in a VM, including a simulated Wi-Fi card |
| [docs/08-real-run.md](docs/08-real-run.md) | Starting the real install, the result, and the deviations |
| [docs/09-lessons.md](docs/09-lessons.md) | The lessons, technical and procedural |

## The files

```
stick/                      what goes on the USB stick, besides the installer itself
  autoinstall.yaml          the installer's answer file (password hash is a placeholder)
  boot/grub/grub.cfg        the stick's boot menu
  payload/early.sh          runs in the installer before the disk is touched
  payload/target-setup.sh   runs inside the new system at the end of the install
  payload/firstboot.sh      runs once on the new system's first boot
  payload/bocabell-firstboot.service
  payload/wifi.nmconnection.example
test/                       VM test helpers; never put these on the real stick
  test-ap.sh                simulated Wi-Fi card + access point inside the VM
  collect.sh                saves installer-side evidence to the new disk
  checklist.sh              acceptance checks against the installed disk
  shot.py, powerdown.py     drive a QEMU VM through its QMP socket
```

The scripts under `stick/` are the exact files that performed the successful
install. They are **specific to that install**: the hostname `BocaBell`, the
user `tara`, the timezone, and the package list are written into them. Change
those for your own machine, then re-test (see docs/07).

## Not in this repository

- The Ubuntu installer files (download the ISO; docs/06).
- The Claude Code program (`claude.xz`) and the `.deb` packages (docs/06 says
  how to produce them).
- Anything secret: the account's password hash, the Wi-Fi name and key, the
  Claude sign-in token, the restored memory and conversations.

## The three facts to take away if you read nothing else

1. **The installer must not live on the disk it erases.** If it does, a
   failure leaves you with nothing to boot. Put it on removable media, and
   make that media useful for recovery.
2. **A passing test is only as good as its resemblance to the real machine.**
   Three VM runs passed over a wired network. The laptop has only Wi-Fi, and
   on Wi-Fi the installer would have erased the disk and then failed
   (docs/05, "The Wi-Fi trap").
3. **Anything that needs the internet must be proven reachable before the
   disk is touched**, and the proof must not depend on a single server name.
