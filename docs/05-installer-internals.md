# 5. Installer internals the design depends on

Ubuntu's installer is **subiquity**. It runs from a snap inside the live
system. Its full Python source is on the installer image, so its behaviour
can be read instead of guessed:

```bash
sudo mount -o loop,ro ubuntu-26.10-live-server-amd64.iso /mnt/srv
sudo mount -o loop,ro /mnt/srv/casper/ubuntu-server-minimal.squashfs /mnt/srvmin
sudo mount -o loop,ro /mnt/srv/casper/ubuntu-server-minimal.ubuntu-server.squashfs /mnt/srvstd
sudo mount -o loop,ro /mnt/srv/casper/ubuntu-server-minimal.ubuntu-server.installer.squashfs /mnt/srvinst
sudo mount -o loop,ro /mnt/srvinst/var/lib/snapd/seed/snaps/subiquity_*.snap /mnt/srvsnap
# source:  /mnt/srvsnap/lib/python3.12/site-packages/subiquity  and  .../subiquitycore
```

Everything below was read from that source (subiquity snap revision 7477,
netplan 1.2.2) and then confirmed in a VM. File and function names are given
so you can re-check against your own image; line numbers will differ.

## Start-up order

`subiquity/server/server.py`, `SubiquityServer.start()`:

```
1. controllers.load_all()               ← every controller's __init__ runs here
2. start API server, wait for cloud-init
3. select and load the answer file, "early" part only
4. run early-commands                   ← early.sh runs here
5. re-read the answer file              (early-commands may edit /autoinstall.yaml)
6. controllers' start()                 ← network devices are probed here
7. apply_autoinstall_config(), controller by controller
8. install
```

Two consequences:

- **The network controller reads the existing netplan files in step 1,
  before early-commands.** (`BaseNetworkController.__init__` →
  `parse_netplan_configs()`.) Anything `early.sh` writes into
  `/etc/netplan` is not in that snapshot.
- The answer file is copied to `/autoinstall.yaml` and re-read after
  early-commands. An early-command can therefore change the answers. (Not
  used in the final design, but it is the supported way to inject, for
  example, a `network:` section.)

## The answer file and the kernel command line

- The file is picked up from `/cdrom/autoinstall.yaml` (the root of the
  stick) with no extra kernel parameter.
- `autoinstall` on the kernel command line suppresses the "Continue with
  autoinstall?" confirmation.
- `noprompt` suppresses casper's "remove the installation medium" prompt at
  shutdown. In non-interactive mode subiquity also creates
  `/run/casper-no-prompt`.
- A failing early-command aborts the install
  (`AutoinstallUserSuppliedCmdError`) and nothing has been partitioned yet.
- The user in `identity:` is **not** created during the install. It is
  written as cloud-init configuration and created on the new system's first
  boot. Late-commands cannot put files in the user's home.

Validate an answer file with the installer's own validator before using it
(docs/06).

## The Wi-Fi trap

Assume `early.sh` joins Wi-Fi the obvious way on a server system: write
`/etc/netplan/60-wifi.yaml` with a `wifis:` section, `netplan apply`. The
link comes up, the internet check passes. Then, in step 7:

`subiquity/server/controllers/network.py`, `apply_autoinstall_config()` — the
answer file has no `network:` section, so:

```python
if not await self.model.is_nm_enabled():
    await self.initial_config
    self.update_initial_configs()
    self.apply_config(context)
```

`subiquitycore/controllers/network.py`, `_write_config()`:

```python
config = self.model.render_config()
for p in netplan.configs_in_root(self.root, masked=True):
    if p == self.netplan_path:
        continue
    os.rename(p, p + ".dist-" + self.opts.project)     # ← 60-wifi.yaml is renamed away
write_file(self.netplan_path, ...)                      # ← 00-installer-config.yaml, no Wi-Fi in it
```

The model's Wi-Fi device has an empty configuration, because the snapshot
from step 1 predates `early.sh`; `render_config()` skips devices with no
configuration. So the rewritten configuration has no Wi-Fi.

Then `_apply_config()` runs `netplan apply`. In netplan's `apply.py`:

```python
wpa_services = ['netplan-wpa-*.service']
utils.systemctl('stop', wpa_services, sync=sync)
```

The Wi-Fi service is stopped and, with no Wi-Fi in the new configuration,
never started again. Back in `apply_autoinstall_config()`:

```python
self.model.has_network = self.network_event_receiver.has_default_route   # False
```

Now the part that turns an inconvenience into data loss.
`subiquity/server/controllers/mirror.py`,
`find_and_elect_candidate_mirror()`:

```python
if not self.app.base_model.network.has_network:
    log.debug("Skipping mirror check since network is not available.")
    return
```

It returns normally. `fallback: abort` only acts when a mirror check was
*attempted and failed*. With no network, there is no check and no abort. The
install continues: the disk is partitioned, the base system is copied from
the stick (needs no network), and the first failure is the late-command that
tries to download packages.

Variants that do not fix it:

- **Supplying a `network:` section with the Wi-Fi details** (statically, or
  injected by `early.sh`). The installer applies it at start-up, which runs
  `netplan apply`, which stops and restarts the Wi-Fi service. The installer
  samples `has_default_route` immediately afterwards, with no wait for the
  Wi-Fi device (its wait for DHCP only covers devices that already had a
  DHCP configuration in the snapshot). The link is still re-associating:
  `has_network` is very likely `False`, same outcome.
- **Having netplan Wi-Fi in place before the snapshot.** Then the device has
  a DHCP configuration and the installer waits for it after `netplan apply`,
  but for at most 10 seconds. Re-association plus DHCP on a real network can
  exceed that. A race, not a fix.
- Note that netplan with the networkd backend also refuses `wifis:` entries
  that use `match:`; the interface must be named.

## The way out: NetworkManager

Same function, the other branch:

```python
else:
    log.debug("NetworkManager is enabled and no network autoinstall section was found."
              " Not applying network settings.")
    want_apply_config = False
...
self.network_event_receiver.probe_default_routes()
self.model.has_network = self.network_event_receiver.has_default_route
```

`is_nm_enabled()` runs `nmcli networking` and checks for `enabled`. If so,
the installer applies nothing, bounces nothing, and takes `has_network` from
a route that has been stable since `early.sh` checked it. This is the path
the Ubuntu **Desktop** installer always takes, since its live system runs
NetworkManager.

And if that check ever failed, the netplan path still would not harm a
NetworkManager-owned link: `netplan apply` only stops `netplan-wpa-*`
services and only reconfigures interfaces that networkd manages; the
installer only takes down devices whose netplan configuration changed.

So `early.sh` does this when it finds a wireless interface and no internet:

```bash
dpkg -i "$P"/debs/*.deb       # network-manager, wpasupplicant and their dependencies
install -m 600 "$P/wifi.nmconnection" /etc/NetworkManager/system-connections/wifi.nmconnection
systemctl restart NetworkManager
wait_online 60 || true
```

Useful properties:

- The profile file is the same one `target-setup.sh` installs into the new
  system. One file, two uses.
- Ubuntu's `network-manager` package ships
  `/usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf`
  (`unmanaged-devices=*,except:type:wifi,…`). On a server-style system
  NetworkManager therefore manages **only** Wi-Fi and leaves any wired card
  to networkd. No extra configuration is needed.
- The packages install offline with plain `dpkg -i`; how to find the exact
  set is in docs/06.

Evidence from the test and the real run, in
`/var/log/installer/subiquity-server-debug.log` on the installed system:

```
new_link 3 wlan0 wlan
wpasupplicant already installed
NetworkManager is enabled and no network autoinstall section was found. Not applying network settings.
has_network True
```

## Other behaviours worth knowing

**Wi-Fi support package.** When the installer sees a wireless device it
tries to install `wpasupplicant` into the live system from the image's
`pool/` (`subiquity/server/pkghelper.py`). If the package is already
installed it reports `DONE` without touching `pool/`. It then also installs
`wpasupplicant` into the new system, from the network.

**Packages the installer adds itself.** `ssh: install-server: true` and the
Wi-Fi package are installed into the new system by the installer, before
late-commands, from the network when `pool/` is absent.

**Security updates at install time.** By default (`updates: security`) the
installer downloads and installs security updates into the new system before
late-commands. This is a one-time step; it is separate from the
`unattended-upgrades` package, which `target-setup.sh` removes.

**Kernel version.** Because packages come from the network, the new system
can end up on a newer kernel than the stick's live system. Here the stick
ran 7.3.0-9 and the installed system came up on 7.3.0-10.

**Disk choice.** `storage: layout: {name: direct, match: {size: largest}}`
picks the largest disk. With a 1.9 GB stick and a 1 TB drive that is
unambiguous. Think again if the installer medium could be the larger device.

**Logs.** The installer copies its logs to `/var/log/installer/` on the new
system. The live system's own files (for example `early.sh`'s log) are lost
at reboot unless a late-command copies them (see `test/collect.sh`).

**Server image quirk.** `/etc/sudoers` is mode 0644 on the Server image
(`sudo-rs`). `visudo -c` without `-f` reports that as a failure.
