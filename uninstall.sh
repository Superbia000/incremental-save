#!/bin/bash
#
# SillyTavern Incremental Save - Uninstaller
#
# Reverses patches from a running SillyTavern Docker container
# or a local SillyTavern installation.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$SCRIPT_DIR/patches"

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

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

if [ "$MODE" = "docker" ]; then
    if ! docker inspect "$CONTAINER" &>/dev/null; then
        error "Container '$CONTAINER' not found."
    fi

    info "Reversing patches in container '$CONTAINER'..."
    docker cp "$PATCHES_DIR" "$CONTAINER:/tmp/_inc_save_patches"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -R -p1 < /tmp/_inc_save_patches/chats.server.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -R -p1 < /tmp/_inc_save_patches/script.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -R -p1 < /tmp/_inc_save_patches/group-chats.patch"
    docker exec "$CONTAINER" rm -rf /tmp/_inc_save_patches

    info "Restarting container..."
    docker restart "$CONTAINER"
    sleep 3
    info "Done! Incremental save has been removed."
fi

if [ "$MODE" = "local" ]; then
    if [ ! -f "$ST_DIR/server.js" ]; then
        error "'$ST_DIR' does not look like a SillyTavern installation."
    fi

    info "Reversing patches..."
    cd "$ST_DIR"
    patch -R -p1 < "$PATCHES_DIR/chats.server.patch"
    patch -R -p1 < "$PATCHES_DIR/script.patch"
    patch -R -p1 < "$PATCHES_DIR/group-chats.patch"

    info "Done! Restart SillyTavern to revert to full saves."
fi
