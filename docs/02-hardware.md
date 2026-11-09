# 2. Hardware and constraints

## The machine

| Part | Detail | Why it matters |
|---|---|---|
| Laptop | Lenovo Flex 5-1570 (type 81CA), UEFI, Secure Boot off | Boots removable media through a firmware boot entry |
| Graphics | Intel UHD 620, `i915` driver | Works out of the box on Ubuntu |
| Wi-Fi | Qualcomm Atheros QCA6174, `ath10k_pci` driver, firmware `WLAN.RM.4.4.1-00309` | The only network. Driver and firmware are in the Server installer's live system |
| Ethernet | None | **Everything, including the installer's downloads, goes over Wi-Fi** |
| Disk | 1 TB spinning hard drive (`sda`) | Slow: the real install took 55 minutes against 19 in a VM |
| USB stick | 1.9 GB (2,048,729,600 bytes) | Smaller than any Ubuntu installer image |
| Memory | 32 GB fitted, 16 GB detected | Firmware reports one slot empty. A hardware fault, unrelated to the OS, still open |

## Constraints that shaped the design

**The stick is smaller than the installer.** The Ubuntu Desktop 26.10 image
is 6.6 GB. The Server image is 2.9 GB. Neither fits on 1.9 GB. The Server
image, however, is mostly an offline package store that a network install
does not need (docs/03).

**No wired network.** The stock Server installer's live system has no
`wpa_supplicant` installed, so by itself it cannot join a Wi-Fi network with
a password. The packages to do so must travel on the stick.

**The Wi-Fi card can stall.** Once during this work, on the running system,
the card's firmware crashed; the driver reported a successful recovery but
the link carried no traffic for 36 minutes, until Wi-Fi was switched off and
on. It happened once in about 7 hours. The install has no protection against
this happening mid-download; adding it was offered and declined.

**Predictable device names.** With the same kernel in the installer and the
installed system, the Wi-Fi interface is `wlp2s0` in both. The scripts do not
rely on this; they detect the wireless interface.

## What was checked on the real machine before the real run

All read-only, all worth repeating on a different machine:

```bash
lspci -nnk | grep -A3 -i network          # which Wi-Fi chip and driver
[ -d /sys/firmware/efi ] && echo UEFI     # boot mode
mokutil --sb-state                        # Secure Boot state
efibootmgr                                # existing firmware boot entries
cat /sys/class/power_supply/AC*/online    # on mains power
```

And against the installer image (mounted, see docs/06):

```bash
# Is the Wi-Fi driver in the installer's live system?
find /mnt/srvmin/usr/lib/modules -name 'ath10k_pci*'
# Is the card's firmware there?
ls /mnt/srvmin/usr/lib/firmware/ath10k/QCA6174/hw3.0
```

If either is missing for your card, this design does not work as is: the
installer cannot get online, and it will stop before touching the disk.
