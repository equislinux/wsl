# Import and run X Linux on WSL

This guide explains how to turn the tarball produced by `build-rootfs.sh` into
a running X Linux distribution under Windows Subsystem for Linux (WSL). X Linux
for WSL is headless: no GUI, no Hyprland/compositor. It runs `systemd` and is
used from the terminal.

## Prerequisites

- Windows 11 (or Windows 10 with recent updates) with WSL enabled.
  Install it from an elevated PowerShell prompt:

  ```powershell
  wsl --install
  ```

- WSL from the Microsoft Store (not the inbox version) so `systemd` is
  supported. Check the version:

  ```powershell
  wsl --version
  ```

  The version must be at least 0.67.6. Update with `wsl --update` if needed.
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

## 2. Import the distribution

Open PowerShell and import the tarball. The command format is
`wsl --import <Name> <InstallLocation> <Tarball>`:

```powershell
cd $HOME\Downloads
wsl --import x C:\WSL\x .\x-wsl-rootfs.tar.gz
```

Options:

- `--version 2` forces WSL 2 (default when WSL 2 is the default version):
  `wsl --import x C:\WSL\x .\x-wsl-rootfs.tar.gz --version 2`
- Check that the distribution is registered:

  ```powershell
  wsl --list --verbose
  ```

- Make X Linux your default distribution (optional):

  ```powershell
  wsl --set-default x
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

Note that WSL needs about 8 seconds after the last instance closes before a
configuration change is picked up; `wsl --shutdown` forces the restart.

## 4. Configure your user

User provisioning (packages, shell, environment) is handled by
[xlnux/wsl-scripts](https://github.com/xlnux/wsl-scripts). Until then, a manual
user works like this, from inside the distribution (as root):

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
enables `autoMemoryReclaim` and `sparseVhd` for Windows 11. After editing run
`wsl --shutdown`.

## Troubleshooting

- `wsl --import` fails: verify the tarball checksum first (`sha256sum`), make
  sure the target folder does not already hold a registered distribution of the
  same name, and run the command from an elevated prompt if Windows blocks the
  filesystem operation.
- Instance starts but `systemd` is missing: confirm `wsl --version` is recent
  (0.67.6+), `/etc/wsl.conf` contains `[boot] systemd=true`, and restart with
  `wsl --shutdown`.
- Default user errors: WSL refuses to start a session for a user that does not
  exist. Keep `default=root` or point it at a user you have created.
- `pacman` complains about keys after import: run
  `pacman-key --init && pacman-key --populate archlinux` as root inside the
  distribution.
