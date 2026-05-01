#!/bin/bash
#
# SillyTavern Incremental Save + Image Cache - Uninstaller (v1.17)
#
# Reverts patches from a SillyTavern Docker container
# or a local SillyTavern installation.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Detect installation mode ────────────────────────────────────────

if [ "$1" = "--docker" ] || [ "$1" = "-d" ]; then
    MODE="docker"
    CONTAINER="${2:-sillytavern}"
elif [ "$1" = "--local" ] || [ "$1" = "-l" ]; then
    MODE="local"
    ST_DIR="${2:-.}"
else
    echo "Usage:"
    echo "  $0 --docker [container_name]   Revert from Docker container (default: sillytavern)"
    echo "  $0 --local  [sillytavern_dir]  Revert from local installation (default: current dir)"
    exit 1
fi

# ─── Docker mode ─────────────────────────────────────────────────────

if [ "$MODE" = "docker" ]; then
    # Check container exists and is running
    if ! docker inspect "$CONTAINER" &>/dev/null; then
        error "Container '$CONTAINER' not found."
    fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]; then
        error "Container '$CONTAINER' is not running."
    fi

    info "Reverting patches inside container '$CONTAINER'..."

    # Copy patches into container
    docker cp "$SCRIPT_DIR" "$CONTAINER:/tmp/_inc_save_patches"

    # Revert patches (in reverse order)
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -R -p1 < /tmp/_inc_save_patches/tokenizers.1.17.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -R -p1 < /tmp/_inc_save_patches/chats.1.17.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -R -p1 < /tmp/_inc_save_patches/server-startup.1.17.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -R -p1 < /tmp/_inc_save_patches/group-chats.1.17.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -R -p1 < /tmp/_inc_save_patches/script.1.17.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -R -p1 < /tmp/_inc_save_patches/chats.server.1.17.patch"

    # Remove new files
    docker exec "$CONTAINER" rm -f /home/node/app/src/endpoints/image-proxy.js

    # Cleanup
    docker exec "$CONTAINER" rm -rf /tmp/_inc_save_patches

    info "Restarting container..."
    docker restart "$CONTAINER"
    sleep 3

    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" = "true" ]; then
        info "Done! Container '$CONTAINER' has been reverted to original state."
    else
        error "Container failed to start. Check logs: docker logs $CONTAINER"
    fi
fi

# ─── Local mode ──────────────────────────────────────────────────────

if [ "$MODE" = "local" ]; then
    if [ ! -f "$ST_DIR/server.js" ] || [ ! -f "$ST_DIR/public/script.js" ]; then
        error "'$ST_DIR' does not look like a SillyTavern installation."
    fi

    info "Reverting patches..."
    cd "$ST_DIR"
    patch -R -p1 < "$SCRIPT_DIR/tokenizers.1.17.patch"
    patch -R -p1 < "$SCRIPT_DIR/chats.1.17.patch"
    patch -R -p1 < "$SCRIPT_DIR/server-startup.1.17.patch"
    patch -R -p1 < "$SCRIPT_DIR/group-chats.1.17.patch"
    patch -R -p1 < "$SCRIPT_DIR/script.1.17.patch"
    patch -R -p1 < "$SCRIPT_DIR/chats.server.1.17.patch"

    # Remove new files
    rm -f "$ST_DIR/src/endpoints/image-proxy.js"

    info "Done! SillyTavern has been reverted to original state."
fi
