#!/usr/bin/env bash
#
# build-rootfs.sh - build the X Linux for WSL minimal rootfs tarball
#
# Produces <out>/<name>-wsl-rootfs.tar.gz from a pacstrap of the current Arch
# repository state. WSL provides its own kernel, so the "linux" package is NOT
# installed. The result is a headless system (no GUI, no Hyprland/compositor)
# that boots systemd and is meant to be imported with `wsl --import`.
#
# Requires:
#   - an Arch Linux (or Arch-based) host, run as root:
#         sudo ./build-rootfs.sh
#   - arch-install-scripts (pacstrap, arch-chroot), tar, gzip, coreutils
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
    local tool
    for tool in pacstrap arch-chroot tar gzip sha256sum sed; do
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

  Steps:
   1. Check root privileges and required tools
      (pacstrap, arch-chroot, tar, gzip, sha256sum, sed).
   2. mkdir -p '${OUT_DIR}'
      WORK=\$(mktemp -d '${OUT_DIR}/.work.XXXXXX')          (rootfs staging dir)
   3. pacstrap -K -c "\$WORK" ${PACKAGES[*]}
      (-K: init an empty pacman keyring in the target; -c: reuse the host
       package cache. The host mirrorlist is copied into the target so pacman
       works after import.)
   4. mount --bind "\$WORK" "\$WORK"                         (arch-chroot needs a mountpoint)
   5. cp templates/wsl.conf -> "\$WORK/etc/wsl.conf"         (chmod 0644)
      [user] default set to '${WSL_USER}' in /etc/wsl.conf.
      'root' is the safe default for an imported rootfs; WSL boots imported
      distributions as root and refuses to start with a non-existent user.
   6. Write "\$WORK/etc/locale.gen" (enable '${LOCALE}') and
      "\$WORK/etc/locale.conf" (LANG=${LOCALE}).
   7. arch-chroot "\$WORK" locale-gen
   8. arch-chroot "\$WORK" pacman-key --populate archlinux   (best effort)
   9. Remove pacman package cache: find "\$WORK/var/cache/pacman/pkg" -delete
  10. tar -C "\$WORK" --numeric-owner --no-acls --no-xattrs --no-selinux \\
         --one-file-system -cf - . | gzip -9n > '${TARBALL}'
      (root-owned files, no ACLs/xattrs, deterministic gzip header)
  11. sha256sum '${TARBALL}' > '${SHA_FILE}' and print the 'wsl --import' command.
  12. Cleanup: unmount and remove the staging dir (trap on EXIT).
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
cleanup() {
    local rc=$?
    if [[ -n "$WORK" && -d "$WORK" ]]; then
        umount -R "$WORK" >/dev/null 2>&1 || umount -l "$WORK" >/dev/null 2>&1 || true
        rm -rf -- "$WORK"
    fi
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
log "bootstrapping rootfs with pacstrap"
pacstrap -K -c "$WORK" "${PACKAGES[@]}"

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
    log "populating pacman keyring (archlinux)"
    if ! arch-chroot "$WORK" pacman-key --populate archlinux; then
        warn "keyring populate failed; run 'pacman-key --init && pacman-key --populate archlinux' inside WSL"
    fi
fi

# 5. Drop the package cache to keep the tarball small.
log "cleaning pacman package cache"
find "$WORK/var/cache/pacman/pkg" -mindepth 1 -delete 2>/dev/null || true

# 6. Pack the tarball. Preserve ownership (numeric, root) and skip ACLs and
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
sha256sum "$TARBALL" > "$SHA_FILE"
SUM="$(awk '{print $1}' "$SHA_FILE")"

log "rootfs build complete"
cat <<SUMMARY

[x-wsl] Artifact
  File    : ${TARBALL}
  Size    : ${TARBALL_SIZE}
  SHA256  : ${SUM}
            (also saved to ${SHA_FILE})

Import it from PowerShell (copy the tarball to a Windows path first):
  wsl --import ${NAME} C:\\WSL\\${NAME} .\\${NAME}-wsl-rootfs.tar.gz
  wsl --set-default ${NAME}
  wsl -d ${NAME}

The first session starts as root. For user setup, docs and templates see:
  - docs/en/import.md  (or docs/es/import.md) in this repository
  - xlnux/wsl-scripts for user provisioning (default user, packages, shell)
SUMMARY
