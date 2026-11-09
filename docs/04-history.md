# 4. History: what was tried, what failed, why

In order. Each entry: what was done, what happened, the root cause, and what
changed because of it.

## Before: Debian with GNOME added

The laptop ran a Debian server install with GNOME added on top. Problems:

- GNOME did not start on boot; unwanted packages (Firefox ESR) came with it.
- The screen went black and no key or mouse input recovered it. A graphics
  power-state setting (`i915.enable_dc=0`) was proposed as a fix. It was
  rejected as a workaround for an unproven cause, and the cause was never
  proven.
- Only 16 of 32 GB of memory was visible. Time was lost here on things that
  could not help: a firmware-update suggestion made without first checking
  that the firmware was already the latest, and a memory test, which tests
  memory the system can see, not memory it cannot. The firmware itself
  reports the second slot as empty, so this is hardware.

The same laptop had previously worked well under Ubuntu Desktop.
**Decision: start over on Ubuntu.**

Lesson: check the cheap fact before proposing the expensive step. A proposal
that turns out to be a no-op costs the other person time.

## Attempt 1: installer on the hard disk, launched from the old system

**Design.** Copy the Ubuntu Desktop installer's files to a spare partition
of the hard disk and boot it through the existing boot loader. The stick
held only a backup of Claude Code's data and a post-install script.

**Result.** Failed at boot.

**Root causes.**

1. An earlier, abandoned copy of installer files was still sitting on
   another partition. The installer's boot code (casper) searches every
   disk for something that looks like its medium and picked the stale copy,
   which had an empty answer file. It then loaded 11 GB into RAM.
2. The intended copy was itself incomplete: `EFI/boot/grub*.efi` was
   missing.

**Changes.** Copy completely and verify against the image's checksums. Pin
the medium explicitly. Remove leftovers before starting; unused partitions
"getting in the way" were part of the problem.

**Also learned.** The offer to recover the half-done install in place was
refused: a recovered install is a low-confidence install. Fix the cause and
run again from the start (requirement P5).

## Attempt 2: same design, corrected

**Result.** An operating system was installed. The attempt was still a
failure:

- One identity screen appeared and had to be filled in by hand.
- "Remove the installation medium" was displayed. The stick was removed.
- Automatic login was not set.
- All the requested software depended on a post-install script that a person
  had to run. It never ran.
- Claude Code had to be installed by hand.

**Root cause.** The design had two parts: an install, then a manual script.
Every item above is a consequence of that, or of an answer file that did not
answer everything. A process that needs a person in the middle is not
unattended.

**What not to do next.** Arguing that the install "had not really failed"
because an OS existed. It failed the stated requirement. Go to the cause.

**Changes.** Requirements P1–P4. One pass. A complete answer file.
`noprompt`. Software installed by the installer's own late-commands.

## Redesign A: one pass, installer still on the hard disk

**Result.** Rejected before running.

**Root cause.** The installer, the backups and the build files all lived on
the partition that the install would erase. Any failure after partitioning
would leave no installer, no backup, and no system. This is requirement P6.

## Redesign B: the stick is the installer

**Obstacle: the stick is 1.9 GB.** The Desktop image is 6.6 GB.

- First idea: the Server image. It is 2.9 GB. Claimed to fit before
  measuring. It does not.
- Measured it: 1,139 MB of the 2.9 GB is `pool/`, the offline package store.
  Without it the image is about 1.6 GB.

**Question that had to be answered by test, not assumption:** the installer
still lists the stick as a package source. With the files gone, does `apt`
fail, or fall back to the network?

Test: a throwaway `apt` configuration with two sources, a local `file://`
source containing only the package index (no `.deb` files) and the network
archive, then `apt-get install -d --reinstall <pkg>`. Result: `apt` fetched
from the network. The design stands.

**Obstacle: Claude Code for rescue (P7).** The request was to have it
already present in the installer's environment, because installing it by
hand in a failed-install shell "is a lot of work by itself". The program is
340 MB; compressed with `xz -6` it is 111 MB, which fits.

**Obstacle: Claude Code's installer needs the network.**
`claude install` was tested inside a network namespace with no interfaces.
It fails even when given the program locally. So the files are placed
directly in the native-install layout (docs/03).

## VM test 1: no network

Booted the real stick in a VM with no network card.

- The stick booted under UEFI; the answer file was found automatically.
- Claude Code ran in the installer's shell and listed the restored data.
- The install stopped with the virtual disk untouched.

**Fault found:** Claude Code keeps conversations filed by the directory it
was started in. Started from an arbitrary directory in the installer's
shell, `claude --resume` would not list the restored ones. Fix: the program
moved to `/usr/local/lib/bocabell/claude`, with a two-line wrapper at
`/usr/local/bin/claude` that always starts it in `/root`, where the restored
conversations are also filed.

## VM test 2: full install, wired network

**Bug 1: the `sudo` check.** `target-setup.sh` validated its new rule with
`visudo -c`, which checks every sudo file. The Server image ships
`/etc/sudoers` with mode 0644 (it uses `sudo-rs`), and `visudo` reports
that as an error. The script stopped. On the real machine this would have
been a failure after the disk was erased.
Fix: `visudo -c -f /etc/sudoers.d/tara`, checking only the file the script
wrote.

**Bug 2: the stick's hand-off to an installed system.** The boot-menu entry
that boots an already-installed system chain-loaded the hard drive's
`shimx64.efi`. The shim then could not find its `grubx64.efi`.
Fix: locate the disk by the marker file, set `root` and `prefix`, and load
the installed system's own menu with `configfile`.

The run was pushed to the end by hand to look for further bugs. Because of
that manual help it was **not** counted as a pass.

**A test-method trap.** Running the setup script as a background job on the
VM's console froze `apt`: a background process that touches the terminal is
stopped by the kernel (SIGTTOU). Detach it properly
(`setsid … </dev/null`). This was a fault of the test, not of the stick.

## VM test 3: clean, hands-off

Two more bugs before it passed. Each stopped the run at the internet check,
before the disk was touched; each needed a fix on the stick and a restart
from an empty disk.

**Bug 3: impatient internet check.** One 8-second attempt. A network that
is still coming up fails it. Fix: `wait_online N`, retrying every 3 seconds;
separate waiting times for "Wi-Fi being brought up" and "wired network
still starting".

**Bug 4: one server name.** The check asked `archive.ubuntu.com` only.
During the test that name was unreachable from this network while Ubuntu's
other servers were fine. Fix: "online" means *any one* of four Ubuntu
servers answers. And the answer file now lists download servers explicitly,
in order, with `fallback: abort`.

Then the run passed: empty disk to logged-in desktop in 19 minutes with no
input, and every item on the checklist present.

**At this point the answer to "are we ready?" was almost "yes".**

## The defect no VM run had shown

Asked directly whether it was safe to start, one fact stood out: all three
runs used a wired network, and the laptop has none. The Wi-Fi branch of
`early.sh` had never executed with a wireless device present. Rather than
assume, the installer's source was read (it is on the image, docs/05).

Finding: with Wi-Fi brought up through netplan, as `early.sh` then did, the
installer would

1. rewrite the network configuration from a snapshot taken *before*
   `early.sh` ran, which contains no Wi-Fi;
2. apply it, which stops the Wi-Fi service;
3. record "no network";
4. **skip** its download-server check because there is no network, so
   `fallback: abort` never fires;
5. erase the disk and install the base system from the stick;
6. fail when `target-setup.sh` tries to download the desktop.

A wiped disk and no desktop: the worst available outcome, and exactly what
the internet check was meant to prevent.

Fix: NetworkManager owns the Wi-Fi link in the installer (docs/05).

## VM test 4: simulated Wi-Fi

A VM has no Wi-Fi card, so one was simulated (docs/07): the kernel's
`mac80211_hwsim` module gives two virtual radios; one became an access point
with the real network's name and key, the VM's wired card was hidden in a
separate network namespace behind it, and the other radio was left as "the
laptop's Wi-Fi card".

First start: stopped on a syntax error in the test's own firewall rule.
Before the disk was touched, as designed. Fixed, restarted.

Second start: passed. 19 minutes, no input. The installer's log shows the
intended path: `NetworkManager is enabled and no network autoinstall section
was found. Not applying network settings.` and `has_network True`. Wi-Fi was
still connected when the late-commands ran.

## One more observation before the real run

While the last test finished, the laptop's own Wi-Fi card stalled for 36
minutes (docs/02). A recovery mechanism for the installer was offered
(restart Wi-Fi when the internet drops, retry downloads) at the cost of one
more test run. It was declined. The real run went ahead without it and did
not hit the problem.

## The real run

Succeeded. See docs/08.

## Summary table

| # | Failure | Found by | Would have happened on the real machine |
|---|---|---|---|
| 1 | Stale installer copy picked up; partial copy | Real attempt 1 | — |
| 2 | Manual steps, prompts, missing settings | Real attempt 2 | — |
| 3 | Installer on the disk it erases | Review of the plan | No fallback after any failure |
| 4 | Image larger than the stick | Measuring | Could not build the stick |
| 5 | `visudo -c` trips on a file Ubuntu ships | VM test 2 | Failure after the disk was erased |
| 6 | Chain-loading the installed shim fails | VM test 2 | Reboot with stick in → no boot |
| 7 | Internet check gives up after 8 s | VM test 3 | Install refuses to start |
| 8 | Internet check trusts one server name | VM test 3 | Install refuses to start |
| 9 | Installer switches netplan Wi-Fi off, then erases | Reading source | **Disk erased, no desktop** |
