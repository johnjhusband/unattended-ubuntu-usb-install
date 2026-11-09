# 7. Testing in a VM

The principle: boot the **real stick**, not a copy of the idea of it, against
an empty virtual disk, and let it run with nobody touching it. Then shut the
VM down and inspect the disk it produced from outside.

A run counts as a pass only if it went from an empty disk to the desktop
with no input at all. A run that was helped along by hand finds bugs, but it
is not a pass.

## Tools

```bash
sudo apt-get install -y qemu-system-x86 qemu-utils ovmf netpbm
```

KVM for speed, OVMF for UEFI firmware (the laptop is UEFI), QMP (QEMU's
control socket) for screenshots and power, `qemu-nbd` to mount the VM's
disk on the host afterwards.

## Start a run

```bash
V=~/install-build/vm; mkdir -p $V
qemu-img create -q -f qcow2 $V/t.qcow2 40G
cp /usr/share/OVMF/OVMF_VARS_4M.fd $V/t_VARS.fd          # fresh firmware settings every run

sudo qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 4 -m 6144 \
 -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
 -drive if=pflash,format=raw,file=$V/t_VARS.fd \
 -device qemu-xhci,id=xhci \
 -drive if=none,id=stick,file=/dev/sdb,format=raw,snapshot=on \
 -device usb-storage,bus=xhci.0,drive=stick,bootindex=0,removable=on \
 -drive if=none,id=hd,file=$V/t.qcow2,format=qcow2,cache=unsafe \
 -device ide-hd,drive=hd,bus=ide.0,bootindex=1 \
 -nic user,model=e1000e \
 -display none -vga std \
 -qmp unix:$V/qmp.sock,server=on,wait=off \
 -serial file:$V/serial.log -daemonize -pidfile $V/qemu.pid
```

Points that matter:

- `file=/dev/sdb … snapshot=on` boots the physical stick but discards
  anything the VM writes to it. Unmount the stick on the host first.
- The stick is attached as USB storage with `bootindex=0`, the disk as
  `bootindex=1`. The stick stays "plugged in" across the VM's reboot, which
  also tests the boot menu's "already installed" guard.
- A new, empty `qcow2` and a fresh `_VARS.fd` for every run. Never reuse a
  disk from a failed run.
- `-m 6144`: the live system unpacks a 340 MB program into RAM and runs an
  installer; give it room.
- For the "no network" test, replace `-nic user,…` with `-nic none`.

## Watch it

```bash
sudo python3 test/shot.py $V/qmp.sock /tmp/s.ppm 280    # screenshot after 280 s
pnmtopng /tmp/s.ppm > /tmp/s.png
ls -la $V/t.qcow2                                        # is the disk still growing?
```

The installer prints its progress as `start:` / `finish:` lines, so a
screenshot shows which step it is on. A failed early- or late-command ends
with "An error occurred. Press enter to start a shell".

## Inspect the result

```bash
sudo python3 test/powerdown.py $V/qmp.sock               # after the desktop appears
# wait for the qemu process to exit, then:
sudo modprobe nbd max_part=8
sudo qemu-nbd -r -c /dev/nbd0 $V/t.qcow2
sudo mkdir -p /mnt/t && sudo mount -o ro,noload /dev/nbd0p2 /mnt/t
bash test/checklist.sh /mnt/t
sudo umount /mnt/t && sudo qemu-nbd -d /dev/nbd0
```

Inspecting the disk from the host is far more reliable than typing commands
into the VM's desktop through simulated keystrokes.

The decisive lines of the checklist:

- `installed as required: 14 of 14`, `absent as required: 5 of 5`
- `first boot: == first boot done`, `markers: 2`, `leftover payload: 0`
- `curtin failed steps: 0`, `target-setup reached end: 1`
- on a Wi-Fi run: `NetworkManager is enabled … Not applying network settings`
  and `has_network True`

## The runs to do

| Run | Setup | Must show |
|---|---|---|
| A. No network | `-nic none` | Install stops; virtual disk still empty; `claude` works in the installer's shell |
| B. Wired | as above | Empty disk → desktop, no input; checklist |
| C. Simulated Wi-Fi | below | Same, with the install running over Wi-Fi |

Run C is not optional if the real machine installs over Wi-Fi. Runs A and B
passed here while the design still contained the defect that would have
erased the real disk and then failed (docs/05).

## Run C: simulating a Wi-Fi card

A VM has no Wi-Fi card. The Linux kernel can simulate one:
`mac80211_hwsim` creates virtual radios that can hear each other. The module
is in the Server installer's live system.

The arrangement, all inside the VM's live system:

```
main network namespace                 namespace "ap"
┌───────────────────────┐              ┌──────────────────────────────────────┐
│ wlan0  (station)      │ ~~radio~~    │ wlan1  hostapd, 192.168.77.1         │
│  ← the "laptop Wi-Fi" │              │        dnsmasq: DHCP + DNS forwarder │
│  no wired card here   │              │ wired NIC 10.0.2.15 → QEMU → internet│
└───────────────────────┘              │ nft masquerade, ip_forward=1         │
                                       └──────────────────────────────────────┘
```

The access point uses the SSID and key from the real `wifi.nmconnection`, so
the real `early.sh` and the real profile are exercised unchanged. Hiding the
wired card in the other namespace is what forces `early.sh` down its Wi-Fi
branch.

Do this on a **copy** of the stick, so the real stick never carries test
code:

```bash
sudo dd if=/dev/sdb of=$V/stick-test.img bs=4M conv=fsync
LOOP=$(sudo losetup -fP --show $V/stick-test.img)
sudo mount -o uid=1000,gid=1000 ${LOOP}p1 /mnt/sticktest
mkdir -p /mnt/sticktest/test/debs
cp test/test-ap.sh test/collect.sh /mnt/sticktest/test/
cp hostapd_*.deb dnsmasq-base_*.deb iw_*.deb /mnt/sticktest/test/debs/
```

Get those three packages the same way as the Wi-Fi packages in docs/06
(`apt-get install --download-only --no-install-recommends hostapd
dnsmasq-base iw` inside the scratch copy of the live system).

Add the two hooks to the copy's answer file, and nothing else:

```yaml
  early-commands:
    - bash /cdrom/test/test-ap.sh          # test only
    - bash /cdrom/payload/early.sh
  late-commands:
    - bash /cdrom/test/collect.sh          # test only
    - mkdir -p /target/opt/bocabell
    ...
```

Unmount, detach the loop device, and start the VM with
`file=$V/stick-test.img` in place of `file=/dev/sdb`.

Afterwards, on the installed disk, `/var/log/bocabell-test/` holds
`early.sh`'s log, the access point's log and a snapshot of the network state
at the start of the late-commands. `state-at-late.txt` should show
`wlan0:wifi:connected:<your SSID>` and a default route through `wlan0`.

Finally, confirm the real stick and the test image differ only by the test
hooks:

```bash
sudo diff -rq /mnt/stick /mnt/sticktest
# expect exactly:  autoinstall.yaml differs;  Only in /mnt/sticktest: test
```

### Pitfalls met while building this test

- `nft` rejects the one-line form
  `table ip t { chain c { …; oifname "x" masquerade; } }`. Write the rule
  set across several lines. Check syntax on the host first, harmlessly:
  `sudo unshare -n nft -f file`.
- Start `hostapd` and `dnsmasq` with `systemd-run --unit=…`, so they are
  their own units and outlive the early-command that launched them.
- `iw` is needed to move a radio into a namespace
  (`iw phy <phy> set netns name ap`) and is not in the live system.
- A mistake in the test hook stops the install at the early-command stage,
  with the virtual disk untouched. That is the abort path working.

## What no VM can show

1. The real firmware booting the stick.
2. The real Wi-Fi card associating from inside the installer. Reduce the
   risk by confirming the installer's live system has the same driver and
   firmware files that are working on the machine now (docs/02).
3. The real graphics hardware on the installed system.
4. Real speed. The VM took 19 minutes; the laptop's hard drive took 55.

Say these out loud before the real run. They are the remaining risk.
