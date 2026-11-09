# 1. Goals

## The request

Reinstall a laptop so that it "works the first time, all the way through",
with no questions asked and no manual steps afterwards.

## Requirements for the finished system

| # | Requirement |
|---|---|
| 1 | Latest stable Ubuntu (26.10 at the time), GNOME desktop |
| 2 | Boots straight to the desktop, automatic login |
| 3 | Hostname `BocaBell`, user `tara`, the existing password carried over without anyone typing it |
| 4 | `sudo` without a password |
| 5 | SSH server installed |
| 6 | Wi-Fi working with the existing network, no setup |
| 7 | Installed: git, tmux, jq, unzip, build-essential, python3-venv, python3-pip, nodejs, npm, curl |
| 8 | Google Chrome installed and on the dock |
| 9 | Firefox not installed |
| 10 | No automatic security upgrades (`unattended-upgrades` removed) |
| 11 | No welcome wizard, no usage reporting, no crash uploader |
| 12 | Ubuntu Pro not wanted (see "Open items") |
| 13 | Claude Code installed, on the path in every terminal, **not signed in** |
| 14 | Claude Code's settings, memory files and past conversations restored |

## Requirements for the process

These were not all stated at the start. Several were discovered by violating
them (docs/04). They are the real specification.

| # | Requirement | How it was learned |
|---|---|---|
| P1 | No question is asked during the install: no hostname screen, no user screen, no confirmation | Attempt 2 showed one identity screen |
| P2 | No "remove the installation medium, then press Enter" prompt | Attempt 2 showed it; the stick was removed, which broke the next step |
| P3 | No post-install script for a person to run. Everything happens inside the one install | Attempt 2 relied on such a script; it never ran |
| P4 | No manual install of any program afterwards, Claude Code included | Attempt 2 |
| P5 | A failed install is not repaired in place. Fix the cause, rerun clean from the start | Attempt 1; an in-place recovery "creates a low-confidence install" |
| P6 | There is always a fallback. The installer must not sit on the disk it erases | Second redesign had exactly this hole |
| P7 | If the install fails, the machine must still offer a usable environment with help in it | Led to Claude Code being preinstalled in the installer's own live system |
| P8 | The person's only action is to approve the start | |
| P9 | Nothing that has not been tested goes to the real machine | Four bugs were found in VM runs, a fifth by reading source |

## What "installed but not signed in" means in practice

Claude Code is copied onto the new system and runs (`claude --version`
works on first boot), but no credential file is carried over. The sign-in
token (`~/.claude/.credentials.json`) is deliberately left off the stick. The
person signs in once after the install. Settings, memory and conversations
are carried, because they are not credentials.

## What the stick is allowed to hold

The stick holds two sensitive things, with the owner's knowledge:

- the account's password **hash** (in the answer file), so no one types a
  password;
- the Wi-Fi profile with its key, so the installer can get online.

Treat the stick as sensitive afterwards. Nothing else secret is on it.

## Open items at the end

- **Ubuntu Pro packages** are still installed; only their services and
  prompts are switched off. Removing `ubuntu-pro-client` also removes the
  Software Updater, the release upgrader and the desktop metapackages, so the
  outright removal was not done.
- **`dmidecode`** was on the "not wanted" list but cannot be removed: the
  disk-partitioning library depends on it and the desktop depends on that.
- **Wi-Fi recovery during the install** was offered and declined
  (docs/08).
