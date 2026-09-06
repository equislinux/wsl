# Architecture

This document explains how the X Linux WSL experience is put together across
the repositories of the [xlnux](https://github.com/xlnux) organization and how
the pieces map to the official WSL documentation
(https://learn.microsoft.com/windows/wsl). It is the counterpart of
`docs/architecture.md` in the `xlnux/wsl-scripts` repository, seen from the
distro/import side.

## The end-to-end flow

X Linux for WSL is headless (terminal only). Two repositories plus the Windows
host produce a running, provisioned distribution:

```
  xlnux/wsl                  xlnux/wsl            xlnux/wsl-scripts
  (Arch host)                (Windows host)       (inside the distro)
  ----------------           ----------------     ----------------
  1. build-rootfs.sh         2. install.ps1       3. install.sh (root)
     pacstrap of a minimal      wsl --import         system stage:
     Arch rootfs, with a         --version 2          locale, keymap,
     default /etc/wsl.conf       (WSL 2)              timezone, tools,
     (systemd on, [user]         wsl --set-default    sudo user; pins
     default=root, [time])                            [user] default
                                  4. exit, relaunch
        out/x-wsl-rootfs.tar.gz    5. install.sh (user)
                                          user stage: shell, env, folders
```

`wsl` is the *distro* repository: it produces the importable rootfs and hosts
the Windows-side importer. `wsl-scripts` is the *setup* repository: it runs
inside the imported distribution and configures the system and the user. Each
repository is independent, with its own origin and release on `main`.

## Repository layout

| File                 | Role                                                        |
|----------------------|-------------------------------------------------------------|
| `build-rootfs.sh`    | Builds `<name>-wsl-rootfs.tar.gz` with pacstrap on Arch.     |
| `install.ps1`        | Windows importer: checks WSL, imports as WSL 2, sets default, prints `.wslconfig` guidance. |
| `templates/wsl.conf` | Per-distribution config baked into the rootfs as `/etc/wsl.conf`. |
| `templates/.wslconfig` | Host-side global WSL 2 config example (never required).     |
| `docs/en|es/`        | Architecture and import/run guides.                         |
| `out/`               | Build artifacts (git-ignored).                               |

## Mapping to the official WSL documentation

The rootfs ships `/etc/wsl.conf` (built from `templates/wsl.conf`) so that a
freshly imported distribution behaves as a modern, systemd-managed system.
Every key used maps directly to the official settings reference
(https://learn.microsoft.com/en-us/windows/wsl/wsl-config):

| Setting used in `/etc/wsl.conf`      | Official section / key                  | Notes |
|--------------------------------------|-----------------------------------------|-------|
| `[boot] systemd=true`                | [Systemd support](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#systemd-support) | Requires the Microsoft Store build of WSL and Windows 11 (or Server 2022). |
| `[user] default=root` initially      | [User settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#user-settings) | Imported distributions boot as root until a real user is set here. Changed to the created user by `wsl-scripts`. |
| `[interop] enabled / appendWindowsPath` | [Interop settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#interop-settings) | Keeps Windows interop (running `.exe`, Windows PATH) available. |
| `[network] generateHosts / generateResolvConf` | [Network settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#network-settings) | WSL owns `/etc/hosts` and `/etc/resolv.conf`. |
| `[time] useWindowsTimezone=true`     | [Time settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#time-settings) | The instance clock and timezone follow Windows. |

The host-side `templates/.wslconfig` documents global WSL 2 VM settings
(`memory`, `processors`, `guiApplications=false` for a headless distro, and
the `[experimental]` `autoMemoryReclaim` / `sparseVhd` keys), all described in
[.wslconfig settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#wslconfig).
WSL has no default `.wslconfig`; it must be created in `%UserProfile%`, which
is why `install.ps1` only prints guidance and never overwrites an existing one.
After editing either file WSL must restart to pick the change up (the "8
second rule"); `wsl --shutdown` forces it.

## Why the default user matters

WSL starts a session as the user named by `[user] default` in `/etc/wsl.conf`.
For distributions installed from the Store that value is the first-run user;
for an **imported** distribution there is no first-run wizard and no Windows
launcher, so:

- the value must already exist in the distribution, otherwise WSL refuses to
  start (which is why the rootfs ships `default=root`);
- it can only be changed through `/etc/wsl.conf` - the
  `wslconfig.exe`-style `config --default-user` launcher command does **not**
  work for imported distributions (see "Change the default user for a
  distribution" in the [WSL basic commands](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)).

`build-rootfs.sh` keeps `default=root` by design: a fresh import must boot. The
`wsl-scripts` system stage later creates a real user and rewrites only the
`[user] default` value.

## Import semantics

`install.ps1` uses the current official import command:

```
wsl --import <Name> <InstallLocation> <FileName> --version 2
```

`--version 2` pins the new distribution to WSL 2 regardless of the machine
default. The `<InstallLocation>` is a Windows folder that will hold the
distribution VHD (`ext4.vhdx`); the importer defaults to a per-user path so no
administrator rights are needed. The equivalent `install.ps1` steps are the
manual commands in `docs/en/import.md`. On success it runs
`wsl --set-default <Name>` (optional) and prints the next steps for the setup
in `xlnux/wsl-scripts`.

## Build notes

`build-rootfs.sh` runs on Arch and produces a plain, root-owned tar (no ACLs,
no xattrs, numeric owners). WSL provides its own kernel and networking, so the
`linux`, `linux-firmware`, `networkmanager` and `openssh` packages are
intentionally absent. The result is a headless system that boots systemd once
imported; user provisioning is left to `xlnux/wsl-scripts`.

## Running model

- `build-rootfs.sh` honours `X_DRY=1` (print the plan without touching the
  system; no root required) and is otherwise meant to run with root on Arch.
- Neither build nor import depends on external infrastructure beyond the Arch
  mirrors and the store/online WSL distribution channels.

See `docs/en/import.md` for the step-by-step walkthrough and requirements.
