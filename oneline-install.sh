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
set -eu

REPO="DEEPX-AI/dx-modelzoo"
INSTALL_ROOT="${DX_INSTALL_DIR:-$HOME/deepx}"
VENV="$INSTALL_ROOT/venv-dx-modelzoo"
EXTRA="${DX_EXTRA:-cpu}"

log() { printf '\033[1;34m[dx-modelzoo]\033[0m %s\n' "$1"; }
die() { printf '\033[1;31m[dx-modelzoo][ERROR]\033[0m %s\n' "$1" >&2; exit 1; }

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

    log "Creating venv at $VENV"
    mkdir -p "$INSTALL_ROOT"
    if [ -d "$VENV" ] && [ ! -x "$VENV/bin/python" ]; then
        die "$VENV exists but is not a usable venv (missing bin/python) — remove it and re-run: rm -rf '$VENV'"
    fi
    if [ ! -e "$VENV/bin/python" ]; then
        python3 -m venv "$VENV" \
            || die "venv creation failed — install it first: sudo apt-get install python3-venv"
    fi

    log "Installing dx-modelzoo[$EXTRA] $TAG"
    "$VENV/bin/pip" install --upgrade pip >/dev/null
    "$VENV/bin/pip" install "dx-modelzoo[$EXTRA] @ https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz" \
        || die "pip install failed (tag '$TAG' may not exist — check https://github.com/$REPO/releases)"

    log "Verifying install"
    "$VENV/bin/python" -c "import dx_modelzoo" \
        || die "import check failed — dx_modelzoo did not install correctly"

    log "Done. Activate with:  . $VENV/bin/activate"
}

main "$@"
