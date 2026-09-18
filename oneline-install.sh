#!/bin/sh
# DEEPX dx-modelzoo one-line installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/DEEPX-AI/dx-modelzoo/main/oneline-install.sh | sh
#
# Env overrides:
#   DX_VERSION=vX.Y.Z     pin a release (default: latest release)
#   DX_INSTALL_DIR=<dir>  install root (default: ~/deepx)
#   DX_EXTRA=cpu|gpu      onnxruntime backend to install (default: cpu)
#   DX_NO_UV=1            skip uv and install with pip
#   UV_PIN=X.Y.Z          uv release to bootstrap (default below)
set -eu

REPO="DEEPX-AI/dx-modelzoo"
INSTALL_ROOT="${DX_INSTALL_DIR:-$HOME/deepx}"
VENV="$INSTALL_ROOT/venv-dx-modelzoo"
EXTRA="${DX_EXTRA:-cpu}"

log() { printf '\033[1;34m[dx-modelzoo]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[dx-modelzoo][WARN]\033[0m %s\n' "$1" >&2; }
die() { printf '\033[1;31m[dx-modelzoo][ERROR]\033[0m %s\n' "$1" >&2; exit 1; }

# Pinned so a run never pulls an unreviewed uv release.
UV_PIN="${UV_PIN:-0.12.2}"
UV_BOOTSTRAP_DIR="${UV_BOOTSTRAP_DIR:-$HOME/.local/bin}"

# Make uv available, or return non-zero so the caller falls back to pip. uv is
# fetched as a standalone binary rather than with `pip install uv`: Debian and
# Ubuntu mark their system Python PEP 668 externally-managed, which rejects
# `pip install` even with --user, and getting past that needs
# --break-system-packages, which an installer has no business doing to a distro
# Python. The standalone binary touches no Python installation at all.
ensure_uv() {
    [ "${DX_NO_UV:-0}" = "1" ] && return 1
    command -v uv >/dev/null 2>&1 && return 0

    log "Installing uv ${UV_PIN} to ${UV_BOOTSTRAP_DIR}"
    mkdir -p "$UV_BOOTSTRAP_DIR" || return 1
    # Download, then run — not `curl | sh`. A pipeline reports the last
    # command's status, so a failed download would be handed to sh as empty
    # input and "succeed". A file lets curl's own exit status be checked, and
    # a partial download is never executed.
    _inst="$(mktemp)" || return 1
    if ! curl -LsSf "https://astral.sh/uv/${UV_PIN}/install.sh" -o "$_inst"; then
        rm -f "$_inst"; return 1
    fi
    # UV_NO_MODIFY_PATH keeps the installer out of the user's shell rc files.
    env UV_INSTALL_DIR="$UV_BOOTSTRAP_DIR" UV_NO_MODIFY_PATH=1 sh "$_inst" >&2
    _rc=$?
    rm -f "$_inst"
    [ "$_rc" -eq 0 ] || return 1

    command -v uv >/dev/null 2>&1 && return 0
    PATH="$UV_BOOTSTRAP_DIR:$PATH"; export PATH
    command -v uv >/dev/null 2>&1
}

main() {
    command -v curl    >/dev/null 2>&1 || die "curl is required"
    command -v python3 >/dev/null 2>&1 || die "python3 is required"

    case "$EXTRA" in
        cpu|gpu) ;;
        *) die "DX_EXTRA must be 'cpu' or 'gpu' (got: $EXTRA)" ;;
    esac

    TAG="${DX_VERSION:-}"
    if [ -z "$TAG" ]; then
        log "Resolving latest release tag"
        TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
              | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
        [ -n "$TAG" ] || die "failed to resolve latest release tag (pin with DX_VERSION=vX.Y.Z)"
    fi
    case "$TAG" in
        ''|*..*|/*|*[!A-Za-z0-9._/-]*) die "invalid DX_VERSION: $TAG" ;;
    esac
    [ -z "${DX_REF:-}" ] || warn "DX_REF is ignored by dx-modelzoo; installing $TAG (set DX_VERSION to pin a version)"

    # uv resolves and downloads wheels far faster than pip, which matters here
    # because the dependency set drags in torch and transformers. A uv problem
    # degrades to pip rather than failing the install — both paths install the
    # same packages into the same venv, so the outcome does not depend on which
    # one ran.
    if ensure_uv; then
        INSTALLER="uv"
    else
        INSTALLER="pip"
        [ "${DX_NO_UV:-0}" = "1" ] || warn "uv unavailable; falling back to pip (slower)"
    fi

    log "Creating venv at $VENV"
    mkdir -p "$INSTALL_ROOT"
    if [ -d "$VENV" ] && [ ! -x "$VENV/bin/python" ]; then
        die "$VENV exists but is not a usable venv (missing bin/python) — remove it and re-run: rm -rf '$VENV'"
    fi
    if [ ! -e "$VENV/bin/python" ]; then
        if [ "$INSTALLER" = "uv" ]; then
            # --seed puts pip inside the venv; uv omits it otherwise, and users
            # expect to be able to pip install into their own environment later.
            uv venv --seed --python python3 "$VENV" || die "uv venv failed at $VENV"
        else
            python3 -m venv "$VENV" \
                || die "venv creation failed — install it first: sudo apt-get install python3-venv"
        fi
    fi

    REQ="dx-modelzoo[$EXTRA] @ https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"
    log "Installing dx-modelzoo[$EXTRA] $TAG with $INSTALLER"
    if [ "$INSTALLER" = "uv" ]; then
        uv pip install --python "$VENV/bin/python" "$REQ" \
            || die "uv pip install failed (tag '$TAG' may not exist — check https://github.com/$REPO/releases)"
    else
        "$VENV/bin/pip" install --upgrade pip >/dev/null
        "$VENV/bin/pip" install "$REQ" \
            || die "pip install failed (tag '$TAG' may not exist — check https://github.com/$REPO/releases)"
    fi

    log "Verifying install"
    "$VENV/bin/python" -c "import dx_modelzoo" \
        || die "import check failed — dx_modelzoo did not install correctly"

    log "Done. Activate with:  . $VENV/bin/activate"
}

main "$@"
