# Import and run X Linux on WSL

This guide explains how to turn the tarball produced by `build-rootfs.sh` into
a running X Linux distribution under Windows Subsystem for Linux (WSL). X Linux
for WSL is headless: no GUI, no Hyprland/compositor. It runs `systemd` and is
used from the terminal.

The fastest path is the provided PowerShell importer `install.ps1`; the manual
commands are listed next to it. The official references are the WSL basic
commands (https://learn.microsoft.com/en-us/windows/wsl/basic-commands) and the
configuration guide (https://learn.microsoft.com/en-us/windows/wsl/wsl-config).

## Prerequisites

- Windows 11 (or Windows Server 2022) with WSL enabled. The `[boot] systemd`
  support that the rootfs enables needs Windows 11/Server 2022 and the
  Microsoft Store build of WSL. On Windows 10 the rootfs imports and boots,
  but systemd is not available.
- WSL from the Microsoft Store (not the inbox version). Install WSL without a
  bundled distribution from an elevated PowerShell prompt:

  ```powershell
  wsl --install --no-distribution
  ```

  Check the version and update if needed:

  ```powershell
  wsl --version
  wsl --update
  ```

  If `wsl --version` is not recognized, you are on the inbox version; install
  the Store build (https://apps.microsoft.com/detail/9P9TQF7MRM4R).
- The rootfs tarball from this repository. Build it on an Arch host with
  `sudo ./build-rootfs.sh`, or download a published `out/x-wsl-rootfs.tar.gz`.

## 1. Build the rootfs

On an Arch Linux (or Arch-based) host, from this repository:

```bash
sudo ./build-rootfs.sh
```

This produces `out/x-wsl-rootfs.tar.gz` (plus a `.sha256` checksum file). You
can preview the exact commands first without touching the system:

```bash
X_DRY=1 ./build-rootfs.sh
```

Copy the tarball to a location Windows can read, for example
`C:\Users\<you>\Downloads\x-wsl-rootfs.tar.gz`.

## 2. Import the distribution (recommended)

Open PowerShell in this repository and run the importer. It checks WSL
(Store build), imports the rootfs as WSL 2, makes `x` the default
distribution and prints the host `.wslconfig` guidance plus the next steps:

```powershell
.\install.ps1 -Rootfs .\out\x-wsl-rootfs.tar.gz
```

If PowerShell blocks script execution on your machine, launch it with an
explicit bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Rootfs .\out\x-wsl-rootfs.tar.gz
```

Options: `-Name` (default `x`), `-InstallDir` (default a per-user path under
`%LOCALAPPDATA%`), `-NoDefault` (skip `wsl --set-default`) and
`-CreateWslConfig` (create a starter `%UserProfile%\.wslconfig` when none
exists; an existing file is never overwritten). Run
`Get-Help .\install.ps1` for details.

### Manual alternative

```powershell
cd $HOME\Downloads
wsl --import x C:\WSL\x .\x-wsl-rootfs.tar.gz --version 2
wsl --set-default x
```

- `--version 2` forces WSL 2 regardless of the machine default.
- `<InstallLocation>` (`C:\WSL\x`) is the Windows folder that will hold the
  distribution VHD; use any folder, ideally outside the tarball directory.
- Check that the distribution is registered:

  ```powershell
  wsl --list --verbose
  ```

## 3. Start the distribution

```powershell
wsl -d x
```

The first session opens as **root**: imported distributions always boot as root
until a default user is configured. The shipped `/etc/wsl.conf` already enables
`systemd`; verify it is running:

```bash
ps -p 1 -o comm=
# prints: systemd

systemctl is-system-running
# prints: running (or degrading until user services are configured)
```

If `systemd` is not PID 1, restart WSL after checking `/etc/wsl.conf`:

```powershell
wsl --shutdown
```

WSL needs about 8 seconds after the last instance closes before a
configuration change is picked up; `wsl --shutdown` forces the restart.

## 4. Configure your user

User provisioning is handled by
[xlnux/wsl-scripts](https://github.com/xlnux/wsl-scripts). Clone it where both
root and the future user can read it and run the guided installer (two parts):

```bash
git clone https://github.com/xlnux/wsl-scripts /opt/x-wsl-scripts
cd /opt/x-wsl-scripts
./install.sh            # Part 1 (system), as root
```

The system stage asks for locale, keymap, timezone, user, shell and sudo
policy, then pins the created user as the default user of new WSL sessions in
`/etc/wsl.conf` (imported distributions have no Windows launcher, so
`/etc/wsl.conf` is the only supported way to change the default user). When it
finishes, exit the session and relaunch so WSL applies the new default:

```powershell
wsl --terminate x
wsl -d x
```

The new session opens as your user. Run the installer a second time for the
user stage (shell, environment, folders):

```bash
cd /opt/x-wsl-scripts
./install.sh            # Part 2 (user), as your user
```

A manual user works like this, from inside the distribution (as root), if you
prefer not to use the installer:

```bash
useradd -m -G wheel -s /usr/bin/zsh <username>
passwd <username>
```

Arch Linux does not grant `wheel` sudo rights by default. Uncomment the wheel
line with `EDITOR=nano visudo` (the `%wheel ALL=(ALL:ALL) ALL` line) or add a
drop-in:

```bash
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
```

Then make that user the default for new WSL sessions by editing
`/etc/wsl.conf` and setting the `[user]` section:

```ini
[user]
default=<username>
```

Apply it by restarting the instance:

```powershell
wsl --terminate x
wsl -d x
```

Your next session opens as `<username>`. The `wsl.conf`/`.wslconfig` templates
in `templates/` document every option used here.

## 5. Optional: host-side WSL 2 tuning

Create `%UserProfile%\.wslconfig` (i.e. `C:\Users\<you>\.wslconfig`) from
`templates/.wslconfig` and adapt it to your hardware. It caps the VM memory and
processors, keeps WSLg (GUI support) off since X Linux for WSL has no GUI, and
enables `autoMemoryReclaim` and `sparseVhd` for Windows 11. There is no default
`.wslconfig`; the importer only prints guidance and never overwrites an
existing file (use `install.ps1 -CreateWslConfig` to create a starter when
none exists). Windows also offers a "WSL Settings" application that edits the
same settings. After editing run `wsl --shutdown`.

## Troubleshooting

- `wsl --import` fails: verify the tarball checksum first (`sha256sum`), make
  sure the target folder does not already hold a registered distribution of the
  same name (`wsl --unregister x` removes one), and run the command from an
  elevated prompt if Windows blocks the filesystem operation.
- Instance starts but `systemd` is missing: confirm `wsl --version` works (Store
  build), that the host is Windows 11/Server 2022, that `/etc/wsl.conf`
  contains `[boot] systemd=true`, and restart with `wsl --shutdown`.
- Default user errors: WSL refuses to start a session for a user that does not
  exist. Keep `default=root` or point it at a user you have created.
- `pacman` complains about keys after import: run
  `pacman-key --init && pacman-key --populate archlinux` as root inside the
  distribution.
