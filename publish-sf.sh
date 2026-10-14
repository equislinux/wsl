#!/usr/bin/env bash
#
# publish-sf.sh - build the X for WSL rootfs and publish it to SourceForge FRS
#
# Usage:
#   sudo ./publish-sf.sh                # build + checksum + upload + verify
#   sudo ./publish-sf.sh --skip-build   # upload the existing out/ tarball
#   ./publish-sf.sh --dry-run           # print the plan (no root needed)
#
# Environment:
#   SF_USER   SourceForge account             (default: xscriptor)
#   SF_KEY    SSH key for frs.sourceforge.net (default: ~/.ssh/id_ed25519_sourceforge)
#   SF_PATH   remote FRS directory            (default: /home/frs/project/equislinux/wsl)
#
# Safety: this script only creates the target directory (idempotent) and
# uploads the tarball + its .sha256. It never deletes remote files, and nothing
# is uploaded outside SF_PATH.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SF_USER="${SF_USER:-xscriptor}"
# When run via sudo, HOME is root's; default to the invoking user's SSH key.
INVOKER_HOME="$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)"
SF_KEY="${SF_KEY:-${INVOKER_HOME:-$HOME}/.ssh/id_ed25519_sourceforge}"
SF_PATH="${SF_PATH:-/home/frs/project/equislinux/wsl}"
SF_HOST="frs.sourceforge.net"

DRY=0
SKIP_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY=1 ;;
        --skip-build) SKIP_BUILD=1 ;;
        -h|--help)    sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "publish-sf: unknown option '$arg'" >&2; exit 1 ;;
    esac
done

log() { printf '[publish-wsl] %s\n' "$*"; }
die() { printf '[publish-wsl] error: %s\n' "$*" >&2; exit 1; }

TARBALL="$REPO_DIR/out/x-wsl-rootfs.tar.gz"
SHA_FILE="${TARBALL}.sha256"
PUBLIC_URL="https://sourceforge.net/projects/equislinux/files/wsl/x-wsl-rootfs.tar.gz/download"

if [[ $DRY -eq 0 && $SKIP_BUILD -eq 0 && $EUID -ne 0 ]]; then
    die "run as root to build (sudo $0), or use --skip-build / --dry-run"
fi

# Fail before the (slow) build if the upload key is missing.
if [[ $DRY -eq 0 && ! -f "$SF_KEY" ]]; then
    die "SSH key not found: $SF_KEY (set SF_KEY)"
fi

# ---------------------------------------------------------------------------
# 1. Build (unless --skip-build)
# ---------------------------------------------------------------------------
if [[ $SKIP_BUILD -eq 0 ]]; then
    if [[ $DRY -eq 1 ]]; then
        log "dry-run: would run $REPO_DIR/build-rootfs.sh (needs root)"
    else
        log "building the rootfs (this takes a few minutes) ..."
        ( cd "$REPO_DIR" && ./build-rootfs.sh )
    fi
fi

if [[ $DRY -eq 0 ]]; then
    [[ -f "$TARBALL" ]] || die "missing artifact: $TARBALL"
    if [[ $SKIP_BUILD -eq 1 || ! -f "$SHA_FILE" ]]; then
        log "writing checksum ..."
        ( cd "$(dirname "$TARBALL")" && sha256sum "$(basename "$TARBALL")" > "$(basename "$SHA_FILE")" )
    fi
fi

# ---------------------------------------------------------------------------
# 2. Upload to SourceForge FRS
# ---------------------------------------------------------------------------
RSH=(ssh -i "$SF_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

if [[ $DRY -eq 1 ]]; then
    log "dry-run: would create (if needed): $SF_PATH"
    log "dry-run: would upload: x-wsl-rootfs.tar.gz + .sha256 to $SF_USER@$SF_HOST:$SF_PATH/"
    log "dry-run: would verify: $PUBLIC_URL"
    exit 0
fi

[[ -f "$SF_KEY" ]] || die "SSH key not found: $SF_KEY (set SF_KEY)"

log "ensuring remote directory $SF_PATH ..."
printf 'mkdir %s\n' "$SF_PATH" \
    | timeout 60 sftp -b - -i "$SF_KEY" -o BatchMode=yes "$SF_USER@$SF_HOST" >/dev/null 2>&1 || true

log "uploading (approx. 250 MB; --partial resumes if interrupted) ..."
rsync -e "${RSH[*]}" --partial --info=progress2 \
    "$TARBALL" "$SHA_FILE" "$SF_USER@$SF_HOST:$SF_PATH/"

# ---------------------------------------------------------------------------
# 3. Verify the public URL (SourceForge needs a moment to list it)
# ---------------------------------------------------------------------------
log "verifying public URL (may take a moment) ..."
for i in 1 2 3 4 5 6; do
    code="$(curl -sI -L --max-time 30 -o /dev/null -w '%{http_code}' "$PUBLIC_URL" || true)"
    if [[ "$code" == "200" ]]; then
        log "OK: $PUBLIC_URL (HTTP $code)"
        log "done."
        exit 0
    fi
    log "attempt $i: HTTP $code (retrying in 20s)"
    sleep 20
done
die "upload finished but the public URL did not return 200 yet; check https://sourceforge.net/projects/equislinux/files/wsl/"
