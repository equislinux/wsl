#!/usr/bin/env bash
#
# build-rootfs.sh - build the X Linux for WSL minimal rootfs tarball
#
# Produces <out>/<name>-wsl-rootfs.tar.gz from a pacstrap of the current Arch
# repository state. WSL provides its own kernel, so the "linux" package is NOT
# installed. The result is a headless system (no GUI, no Hyprland/compositor)
# that boots systemd and is meant to be imported with `wsl --import`.
#
# Import references (official WSL docs):
#   - wsl --import <Name> <InstallLocation> <Tarball> --version 2
#     https://learn.microsoft.com/en-us/windows/wsl/basic-commands
#   - /etc/wsl.conf and .wslconfig keys used in templates/
#     https://learn.microsoft.com/en-us/windows/wsl/wsl-config
# systemd under WSL needs the Microsoft Store build of WSL and Windows 11
# (or Windows Server 2022).
#
# Requires:
#   - an Arch Linux (or Arch-based) host, run as root:
#         sudo ./build-rootfs.sh
#   - arch-install-scripts (pacstrap, arch-chroot), tar, gzip, coreutils
#   - curl and gpg when the X layer is enabled (X_WSL_BRANDING=1)
#   - root privileges for the pacstrap/chroot mounts; not a restricted container
#
# Environment overrides (pass them inline to sudo):
#         sudo X_WSL_NAME=x2 ./build-rootfs.sh
#   X_WSL_NAME      artifact and WSL distribution name   (default: x)
#   X_WSL_USER      [user] default in /etc/wsl.conf      (default: root)
#   X_WSL_LOCALE    locale for locale.gen and locale.conf (default: en_US.UTF-8)
#   X_WSL_OUT_DIR   output directory for the tarball     (default: ./out)
#   X_DRY=1         print the command plan and exit      (no root needed)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

NAME="${X_WSL_NAME:-x}"
WSL_USER="${X_WSL_USER:-root}"
LOCALE="${X_WSL_LOCALE:-en_US.UTF-8}"
OUT_DIR="${X_WSL_OUT_DIR:-${REPO_DIR}/out}"
DRY="${X_DRY:-0}"

# X Linux package layer. The rootfs is bootstrapped from the stock Arch
# repositories; this repo installs x-release (identity package) from the
# signed [x] repository so the distribution reports "X Linux" and keeps
# tracking updates with a plain `pacman -Syu`.
X_WSL_BRANDING="${X_WSL_BRANDING:-1}"
X_REPO_URL="${X_REPO_URL:-https://equislinux.github.io/x-repo/repo/x86_64}"
X_REPO_KEY_FPR="${X_REPO_KEY_FPR:-D6C5084942318609F12B2F490C860E4E6A638BBB}"
X_WSL_PACKAGES=(x-release)

TARBALL="${OUT_DIR}/${NAME}-wsl-rootfs.tar.gz"
SHA_FILE="${TARBALL}.sha256"
WSL_CONF_SRC="${REPO_DIR}/templates/wsl.conf"

# Minimal set for an importable, headless, systemd-booted X Linux rootfs:
#   base            Arch meta-package ("basic Arch Linux installation"): bash,
#                   coreutils, glibc, systemd, systemd-sysvcompat, ... WSL
#                   provides the kernel, so 'linux' is deliberately absent.
#   bash            shell (already pulled by base; kept explicit).
#   sudo            privilege elevation for the user provisioned later.
#   pacman-contrib  extra pacman tooling (paccache, checkupdates, ...).
#   git, zsh        tooling and interactive shell used by the user setup.
#   tzdata          timezone database for WSL timezone sync (not pulled by base).
# Not included on purpose: openssh and networkmanager (WSL provides networking
# and interop), linux/linux-firmware (WSL uses its own kernel).
PACKAGES=(base bash sudo pacman-contrib git zsh tzdata)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
    C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_OFF=$'\033[0m'
else
    C_GREEN=''; C_YELLOW=''; C_RED=''; C_OFF=''
fi

log()  { printf '%s[x-wsl]%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%s[x-wsl]%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%s[x-wsl]%s error: %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

require_tools() {
    local tool tools=(pacstrap arch-chroot tar gzip sha256sum sed)
    if [[ "$X_WSL_BRANDING" == "1" ]]; then
        tools+=(curl gpg)
    fi
    for tool in "${tools[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool (is arch-install-scripts installed?)"
    done
}

# ---------------------------------------------------------------------------
# Dry run: print the command plan and exit without touching the system
# ---------------------------------------------------------------------------

if [[ "$DRY" == "1" ]]; then
    cat <<PLAN
[x-wsl] Dry run - no changes will be made. Command plan:

  Distribution name   : ${NAME}
  Default WSL user    : ${WSL_USER}   (must exist in the final rootfs)
  Locale              : ${LOCALE}
  Output directory    : ${OUT_DIR}
  Tarball             : ${TARBALL}
  Checksums file      : ${SHA_FILE}
  Packages (pacstrap) : ${PACKAGES[*]}
  X Linux layer       : $([[ "$X_WSL_BRANDING" == "1" ]] && printf '%s (from %s)' "${X_WSL_PACKAGES[*]}" "$X_REPO_URL" || printf 'disabled (X_WSL_BRANDING=0)')

  Steps:
   1. Check root privileges and required tools
      (pacstrap, arch-chroot, tar, gzip, sha256sum, sed).
   2. mkdir -p '${OUT_DIR}'
      WORK=\$(mktemp -d '${OUT_DIR}/.work.XXXXXX')          (rootfs staging dir)
   3. pacstrap -K -c -C <temp config> "\$WORK" ${PACKAGES[*]}
      (-K: init an empty pacman keyring in the target; -c: reuse the host
       package cache; -C: a copy of the host config with an empty HookDir so
       the build host hooks are not run against the staged rootfs.)
   4. mount --bind "\$WORK" "\$WORK"                         (arch-chroot needs a mountpoint)
   5. cp templates/wsl.conf -> "\$WORK/etc/wsl.conf"         (chmod 0644)
      [user] default set to '${WSL_USER}' in /etc/wsl.conf.
      'root' is the safe default for an imported rootfs; WSL boots imported
      distributions as root and refuses to start with a non-existent user.
   6. Write "\$WORK/etc/locale.gen" (enable '${LOCALE}') and
      "\$WORK/etc/locale.conf" (LANG=${LOCALE}).
   7. arch-chroot "\$WORK" locale-gen
   8. Recreate the pacman keyring inside the target
      (rm -rf "\$WORK/etc/pacman.d/gnupg"; pacman-key --init) and run
      pacman-key --populate archlinux (best effort).
   9. X Linux layer (skip with X_WSL_BRANDING=0):
      - append [x] (SigLevel = Required, Server = ${X_REPO_URL}) to
        "\$WORK/etc/pacman.conf" unless already present
      - curl ${X_REPO_URL}/signing.pub -> "\$WORK/etc/pacman.d/x-repo.pub",
        verify fingerprint ${X_REPO_KEY_FPR}
      - arch-chroot "\$WORK" pacman-key --add ... && --lsign-key <fpr>
      - arch-chroot "\$WORK" pacman -Sy --noconfirm ${X_WSL_PACKAGES[*]}
  10. Remove pacman package cache: find "\$WORK/var/cache/pacman/pkg" -delete
  11. tar -C "\$WORK" --numeric-owner --no-acls --no-xattrs --no-selinux \\
         --one-file-system -cf - . | gzip -9n > '${TARBALL}'
      (root-owned files, no ACLs/xattrs, deterministic gzip header)
  12. sha256sum '<name>' > '<SHA_FILE>' (relative filename) and print the
      'wsl --import ... --version 2' command (install.ps1 automates that on
      Windows).
  13. Cleanup: unmount and remove the staging dir (trap on EXIT).
PLAN
    exit 0
fi

# ---------------------------------------------------------------------------
# Real run
# ---------------------------------------------------------------------------

require_tools

if (( EUID != 0 )); then
    die "must run as root:  sudo ./build-rootfs.sh"
fi

if [[ ! -f "$WSL_CONF_SRC" ]]; then
    die "template not found: $WSL_CONF_SRC (run from a checkout of this repository)"
fi

WORK=""
BOOTSTRAP_CONF=""
NO_HOOKS_DIR=""
cleanup() {
    local rc=$?
    if [[ -n "$WORK" && -d "$WORK" ]]; then
        umount -R "$WORK" >/dev/null 2>&1 || umount -l "$WORK" >/dev/null 2>&1 || true
        rm -rf -- "$WORK"
    fi
    [[ -n "$BOOTSTRAP_CONF" ]] && rm -f -- "$BOOTSTRAP_CONF"
    [[ -n "$NO_HOOKS_DIR" ]] && rm -rf -- "$NO_HOOKS_DIR"
    exit "$rc"
}
trap cleanup EXIT

mkdir -p -- "$OUT_DIR"
WORK="$(mktemp -d -- "${OUT_DIR}/.work.XXXXXX")"
log "staging dir: $WORK"

# Make the staging dir a mountpoint so arch-chroot does not warn.
if ! mountpoint -q "$WORK"; then
    if ! mount --bind "$WORK" "$WORK" >/dev/null 2>&1; then
        warn "could not bind-mount $WORK; chroot steps may print a warning"
    fi
fi

# 1. Bootstrap the root filesystem.
#
# pacman with -r executes hooks chrooted into the target but reads their
# definitions from the *host* HookDir (it is not rebased), so a build host
# with x-release installed would inject its branding/GRUB hooks into the
# staged rootfs. Bootstrap with an empty HookDir: package scriptlets still
# run (that is what applies the branding), post-transaction hooks are not
# needed here.
log "bootstrapping rootfs with pacstrap"
NO_HOOKS_DIR="$(mktemp -d -- "${OUT_DIR}/.nohooks.XXXXXX")"
BOOTSTRAP_CONF="$(mktemp -- "${OUT_DIR}/.pacman.conf.XXXXXX")"
# The directive must live in [options]: the host config ends with the [x]
# repository section, so appending at the end would be ignored.
awk -v dir="$NO_HOOKS_DIR" \
    '!done && /^\[options\]/ {print; print "HookDir = " dir; done=1; next} {print}' \
    /etc/pacman.conf >"$BOOTSTRAP_CONF"
pacstrap -K -c -C "$BOOTSTRAP_CONF" "$WORK" "${PACKAGES[@]}"

# 2. Per-distribution WSL settings. The [user] default is 'root' unless an
#    existing user is requested through X_WSL_USER.
log "writing /etc/wsl.conf (default user: ${WSL_USER})"
cp -- "$WSL_CONF_SRC" "$WORK/etc/wsl.conf"
chown root:root "$WORK/etc/wsl.conf"
chmod 0644 "$WORK/etc/wsl.conf"

if [[ "$WSL_USER" != "root" ]]; then
    if ! grep -qE "^${WSL_USER}:[^:]*:[0-9]+:" "$WORK/etc/passwd"; then
        die "X_WSL_USER '${WSL_USER}' does not exist in the new rootfs; keep 'root' or provision the user first"
    fi
    sed -i "s/^default=.*/default=${WSL_USER}/" "$WORK/etc/wsl.conf"
    log "  -> [user] default set to '${WSL_USER}'"
fi

# 3. Locale defaults.
log "writing locale configuration (${LOCALE})"
{
    printf '# /etc/locale.gen - generated by build-rootfs.sh\n'
    printf '%s UTF-8\n' "$LOCALE"
    if [[ "$LOCALE" != "en_US.UTF-8" ]]; then
        printf 'en_US.UTF-8 UTF-8\n'
    fi
} > "$WORK/etc/locale.gen"
chown root:root "$WORK/etc/locale.gen"
chmod 0644 "$WORK/etc/locale.gen"

printf 'LANG=%s\n' "$LOCALE" > "$WORK/etc/locale.conf"
chown root:root "$WORK/etc/locale.conf"
chmod 0644 "$WORK/etc/locale.conf"

log "generating locales"
arch-chroot "$WORK" locale-gen

# 4. Trust the Arch Linux master keys so pacman works immediately after import.
if [[ "${X_KEYRING_POPULATE:-1}" == "1" ]]; then
    log "initializing and populating the pacman keyring (archlinux)"
    # pacstrap -K initializes the keyring with the *host* gpg, whose agent
    # state does not carry into the chroot (archlinux-keyring's post_install
    # cannot locally sign, and the secret key would be host-generated anyway).
    # Recreate it inside the target so the signing key is generated there.
    rm -rf -- "$WORK/etc/pacman.d/gnupg"
    if ! arch-chroot "$WORK" pacman-key --init; then
        warn "pacman-key --init failed; package signature checks will not work inside WSL"
    fi
    if ! arch-chroot "$WORK" pacman-key --populate archlinux; then
        warn "keyring populate failed; run 'pacman-key --init && pacman-key --populate archlinux' inside WSL"
    fi
fi

# 5. X Linux layer: trust the signed [x] repository and install the identity
#    package. Without it the rootfs reports itself as Arch Linux (the stock
#    /usr/lib/os-release from the filesystem package) and `pacman -Syu` would
#    never deliver X branding. x-release is arch=('any') and has no GUI or
#    GRUB dependencies (its GRUB hook is a no-op without /etc/default/grub).
if [[ "$X_WSL_BRANDING" == "1" ]]; then
    log "enabling the [x] repository (${X_REPO_URL})"
    if ! grep -q '^\[x\]' "$WORK/etc/pacman.conf"; then
        cat >> "$WORK/etc/pacman.conf" <<EOF

[x]
# Trusted by build-rootfs.sh / wsl-scripts (/etc/pacman.d/x-repo.pub).
SigLevel = Required
Server = ${X_REPO_URL}
EOF
    fi

    X_REPO_KEY_FILE="$WORK/etc/pacman.d/x-repo.pub"
    if [[ ! -f "$X_REPO_KEY_FILE" ]]; then
        log "fetching the [x] signing key"
        curl -fsSL "${X_REPO_URL%/}/signing.pub" -o "$X_REPO_KEY_FILE" ||
            die "could not download ${X_REPO_URL%/}/signing.pub (offline? set X_WSL_BRANDING=0 to skip the X layer)"
    fi
    chmod 0644 "$X_REPO_KEY_FILE"

    KEY_FPR="$(gpg --with-colons --show-keys "$X_REPO_KEY_FILE" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
    [[ "$KEY_FPR" == "$X_REPO_KEY_FPR" ]] ||
        die "the [x] key fingerprint is '${KEY_FPR:-none}', expected '${X_REPO_KEY_FPR}'"

    log "trusting the [x] key in the target keyring"
    arch-chroot "$WORK" pacman-key --add /etc/pacman.d/x-repo.pub >/dev/null ||
        die "pacman-key --add failed in the staged rootfs"
    arch-chroot "$WORK" pacman-key --lsign-key "$X_REPO_KEY_FPR" >/dev/null ||
        die "pacman-key --lsign-key failed in the staged rootfs"

    log "installing the X Linux identity (${X_WSL_PACKAGES[*]})"
    arch-chroot "$WORK" pacman -Sy --noconfirm --needed "${X_WSL_PACKAGES[@]}" ||
        die "could not install ${X_WSL_PACKAGES[*]} from [x]"

    if ! grep -q '^PRETTY_NAME="X Linux"' "$WORK/usr/lib/os-release"; then
        die "x-release was installed but /usr/lib/os-release is not X Linux"
    fi
    log "  -> /usr/lib/os-release reports X Linux"
else
    warn "X_WSL_BRANDING=0: skipping the [x] repository and x-release (the distro will report itself as Arch Linux)"
fi

# 6. Drop the package cache to keep the tarball small.
log "cleaning pacman package cache"
find "$WORK/var/cache/pacman/pkg" -mindepth 1 -delete 2>/dev/null || true

# 7. Pack the tarball. Preserve ownership (numeric, root) and skip ACLs and
#    xattrs: WSL imports a plain root-owned tar with no extended attributes.
log "packing ${TARBALL}"
tar -C "$WORK" \
    --numeric-owner \
    --no-acls \
    --no-xattrs \
    --no-selinux \
    --one-file-system \
    -cf - . | gzip -9n > "$TARBALL"

TARBALL_SIZE="$(du -h "$TARBALL" | awk '{print $1}')"
( cd "$(dirname "$TARBALL")" && sha256sum "$(basename "$TARBALL")" > "$(basename "$SHA_FILE")" )
SUM="$(awk '{print $1}' "$SHA_FILE")"

log "rootfs build complete"
cat <<SUMMARY

[x-wsl] Artifact
  File    : ${TARBALL}
  Size    : ${TARBALL_SIZE}
  SHA256  : ${SUM}
            (also saved to ${SHA_FILE})
  Identity: $([[ "$X_WSL_BRANDING" == "1" ]] && printf 'X Linux (x-release from [x])' || printf 'Arch Linux (X_WSL_BRANDING=0)')

Import it from PowerShell (copy the tarball to a Windows path first).
The Windows-side installer install.ps1 does this check + import for you:
  powershell -File install.ps1 -Rootfs .\\${NAME}-wsl-rootfs.tar.gz

Manual equivalent:
  wsl --import ${NAME} C:\\WSL\\${NAME} .\\${NAME}-wsl-rootfs.tar.gz --version 2
  wsl --set-default ${NAME}
  wsl -d ${NAME}

The first session starts as root. For user setup, docs and templates see:
  - docs/en/import.md  (or docs/es/import.md) in this repository
  - install.ps1 in this repository (Windows importer)
  - equislinux/wsl-scripts for user provisioning (default user, packages, shell)
SUMMARY
