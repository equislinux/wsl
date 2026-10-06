# X Linux for WSL

[X Linux](https://github.com/equislinux/x) is an Arch-based Linux distribution. This
repository is the **WSL side of the distro**: it builds and hosts the minimal,
importable root filesystem for Windows Subsystem for Linux (WSL), ships the WSL
configuration templates and provides the Windows-side importer and the import
documentation.

The delivered system is **headless**: no GUI, no Hyprland/compositor, no desktop
packages. It boots `systemd` under WSL and is meant to be used from the
terminal, either as-is or as the base that
[equislinux/wsl-scripts](https://github.com/equislinux/wsl-scripts) turns into a
provisioned X Linux user environment.

## Flow

The build, the import and the first-run setup are handled by two repositories
used in order:

```
equislinux/wsl                     equislinux/wsl-scripts
--------------                --------------------
build-rootfs.sh      ->       import on Windows (install.ps1)
(minimal Arch rootfs)         then, inside the distro:
                              1. ./install.sh as root  (system stage)
                              2. exit, relaunch
                              3. ./install.sh as user  (user stage)
```

See `docs/en/architecture.md` (or `docs/es/architecture.md`) for the full
picture and for how `wsl.conf` / `.wslconfig` / `systemd` map to the official
WSL documentation.

## Repository split

| Repository | Role |
|------------|------|
| `equislinux/wsl` | **This repo**: minimal importable Arch rootfs for WSL (`build-rootfs.sh`), `wsl.conf`/`.wslconfig` templates, `install.ps1` (Windows importer) and import docs. |
| `equislinux/wsl-scripts` | User setup and provisioning on top of the imported rootfs (default user, packages, shell, environment). |
| `equislinux/x` | The distro itself: archiso profile, ISO and install flow. |
| `equislinux/scripts` | Provisioning payload and `x` CLI of the full system. |

The build intentionally stops at a bootable, systemd-managed root filesystem.
User creation and configuration live in `equislinux/wsl-scripts`, which consumes
this rootfs; the initial `[user] default` of `/etc/wsl.conf` is `root` because
an imported distribution always boots as root until a real user is provisioned.

## Repository layout

```
build-rootfs.sh     builds <name>-wsl-rootfs.tar.gz with pacstrap on an Arch
                    host (requires root). WSL provides its own kernel, so no
                    linux package is installed. X_DRY=1 previews the plan.
install.ps1         Windows-side importer: checks WSL (Store), imports the
                    rootfs as WSL 2, sets the default distribution and prints
                    the host .wslconfig guidance and the next steps.
templates/wsl.conf  per-distribution WSL config installed into the rootfs
                    ([boot] systemd, [user], [interop], [network], [time]).
templates/.wslconfig
                    host-side global WSL 2 config example (memory, processors,
                    guiApplications, autoMemoryReclaim, sparseVhd).
docs/en|es/         architecture, import and run guides (English/Spanish).
out/                build output, git-ignored.
```

## Quick start

Build the rootfs tarball on an Arch Linux (or Arch-based) host:

```bash
sudo ./build-rootfs.sh
```

Then, on Windows, import the generated `out/x-wsl-rootfs.tar.gz` with the
provided importer (recommended) from a PowerShell prompt in this repository:

```powershell
.\install.ps1 -Rootfs .\out\x-wsl-rootfs.tar.gz
```

If PowerShell blocks script execution, use an explicit bypass:
`powershell -ExecutionPolicy Bypass -File .\install.ps1 -Rootfs .\out\x-wsl-rootfs.tar.gz`.

The equivalent manual commands are:

```powershell
wsl --import x C:\WSL\x .\x-wsl-rootfs.tar.gz --version 2
wsl --set-default x
wsl -d x
```

After the import, finish the setup with `equislinux/wsl-scripts` (run
`./install.sh` as root, relaunch, then run it again as your user). See
`docs/en/import.md` for the full walkthrough and requirements.

## Requirements

### To build

- Arch Linux or Arch-based host with `arch-install-scripts` (`pacstrap`,
  `arch-chroot`), `tar`, `gzip` and `coreutils`.
- Root privileges (the build mounts chroot filesystems, so it cannot run inside
  a restricted container).
- Network access to the Arch mirrors configured on the host.

### To run (Windows)

- WSL 2 from the Microsoft Store (the inbox version cannot run systemd). Check
  with `wsl --version` and update with `wsl --update`.
- Windows 11 (or Server 2022) for the `[boot] systemd` support that the rootfs
  enables. On Windows 10 the rootfs imports and boots, but without systemd.
- The rootfs tarball from this repository (or a published `out/` artifact).

## Validation

- `bash -n build-rootfs.sh` (shell syntax).
- `X_DRY=1 ./build-rootfs.sh` prints the full command plan and exits 0
  without touching the system.
- `install.ps1` is PowerShell; its syntax cannot be exercised in this Linux
  build environment, so it is kept deliberately simple and must be reviewed on
  a Windows host before first use (see its header comment).

## Status

Under active development. The importable rootfs, the configuration templates,
the Windows importer and the documentation are in place; user provisioning and
the friendly first-run setup live in `equislinux/wsl-scripts`. Progress and
decisions for the WSL initiative live in the workspace `ROADMAP.md` /
`DECISIONS.md`.
