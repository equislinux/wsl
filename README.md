# X Linux for WSL

[X Linux](https://github.com/xlnux/x) is an Arch-based Linux distribution. This
repository is the **WSL side of the distro**: it builds and hosts the minimal,
importable root filesystem for Windows Subsystem for Linux (WSL) together with
the WSL configuration templates and the import documentation.

The delivered system is **headless**: no GUI, no Hyprland/compositor, no desktop
packages. It boots `systemd` under WSL and is intended to be used through the
terminal, either as-is or as the base that `xlnux/wsl-scripts` turns into a
provisioned X Linux user environment.

## Repository split

| Repository | Role |
|------------|------|
| `xlnux/wsl` | **This repo**: minimal importable Arch rootfs for WSL (`build-rootfs.sh`), `wsl.conf`/`.wslconfig` templates and import docs. |
| `xlnux/wsl-scripts` | User setup and provisioning on top of the imported rootfs (default user, packages, shell, environment). |
| `xlnux/x` | The distro itself: archiso profile, ISO and install flow. |
| `xlnux/scripts` | Provisioning payload and `x` CLI of the full system. |

The build script intentionally stops at a bootable, systemd-managed root
filesystem. User creation and configuration live in `xlnux/wsl-scripts`, which
consumes this rootfs; the `[user] default` entry of `/etc/wsl.conf` is set to
`root` because an imported distribution always boots as root until a real user
is provisioned.

## Contents

- `build-rootfs.sh` — builds `<name>-wsl-rootfs.tar.gz` with `pacstrap` on an
  Arch host (requires root). WSL provides its own kernel, so no `linux`
  package is installed. Run `X_DRY=1 ./build-rootfs.sh` to preview the plan.
- `templates/wsl.conf` — per-distribution WSL configuration installed into the
  rootfs (`[boot] systemd`, `[user]`, `[interop]`, `[network]`, `[time]`).
- `templates/.wslconfig` — host-side global WSL 2 configuration example
  (`memory`, `processors`, `guiApplications` off, `autoMemoryReclaim`,
  `sparseVhd`).
- `docs/en/import.md`, `docs/es/import.md` — how to build, import and run X
  Linux on WSL (English and Spanish).
- `out/` — build output, git-ignored.

## Quick start

Build the rootfs tarball on an Arch Linux (or Arch-based) host:

```bash
sudo ./build-rootfs.sh
```

Then, on Windows, import the generated `out/x-wsl-rootfs.tar.gz`:

```powershell
wsl --import x C:\WSL\x .\x-wsl-rootfs.tar.gz
wsl --set-default x
wsl -d x
```

See `docs/en/import.md` for the full walkthrough and requirements.

## Requirements to build

- Arch Linux or Arch-based host with `arch-install-scripts` (`pacstrap`,
  `arch-chroot`), `tar`, `gzip` and `coreutils`.
- Root privileges (the build mounts chroot filesystems, so it cannot run
  inside a restricted container).
- Network access to the Arch mirrors configured on the host.

## Status

Under active development (starter). The importable rootfs, configuration
templates and documentation are in place; user provisioning and the friendly
first-run setup are tracked in `xlnux/wsl-scripts`. Progress and decisions for
the WSL initiative live in the workspace `ROADMAP.md` / `DECISIONS.md`.
