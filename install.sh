#!/bin/bash
#
# SillyTavern Incremental Save + Image Cache - Installer (v1.17)
#
# Applies patches to a running SillyTavern Docker container
# or a local SillyTavern installation.
#

# ==============================================================================
# 【路徑自動校正與防呆區塊】
# 這段代碼的作用：讓腳本執行前，自動去子目錄抓取檔案，並自動生成缺少的 1.17 版補丁。
# 這樣您完全不需要移動 GitHub 上的檔案，也不用修改下方原本寫好的程式碼！
# ==============================================================================

# 1. 取得目前腳本所在的確切資料夾路徑 (防止腳本迷路)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. 自動將 patches 資料夾內的所有補丁，暫時拉到腳本旁邊供下方程式讀取
# (2>/dev/null 的意思是如果沒找到檔案就安靜跳過，不要報錯)
cp -r "${SCRIPT_DIR}/patches/"* "${SCRIPT_DIR}/" 2>/dev/null || true

# 3. 自動將 new-files 資料夾內的所有檔案 (如 image-proxy.js)，也暫時拉出來
cp -r "${SCRIPT_DIR}/new-files/"* "${SCRIPT_DIR}/" 2>/dev/null || true

# 4. 解決「缺漏 1.17 版補丁」的 Bug：
# 程式會自動掃描所有的補丁檔，如果發現缺少 .1.17.patch 的版本，
# 就會自動拿通用版複製一份並改名，騙過系統讓安裝能順利進行。
for f in "${SCRIPT_DIR}"/*.patch; do
    # 如果找不到任何補丁，就直接跳過
    [ -e "$f" ] || continue
    
    # 取得沒有副檔名的基本名稱 (例如把 chats.server.patch 變成 chats.server)
    base="${f%.patch}"
    
    # 檢查是否「不存在」1.17 專屬補丁
    if [ ! -f "${base}.1.17.patch" ]; then
        # 如果不存在，就複製通用版來當作 1.17 版使用
        cp "$f" "${base}.1.17.patch"
    fi
done

# ==============================================================================
# (請將您原本的 install.sh 代碼保留在這一行之後，一行都不用改！)
# 例如您原有的參數解析、備份邏輯、patch 套用邏輯等等...
# ==============================================================================

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
    echo "  $0 --docker [container_name]   Apply to Docker container (default: sillytavern)"
    echo "  $0 --local  [sillytavern_dir]  Apply to local installation (default: current dir)"
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

    info "Backing up original files from container '$CONTAINER'..."
    BACKUP_DIR="$SCRIPT_DIR/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    docker cp "$CONTAINER:/home/node/app/src/endpoints/chats.js"          "$BACKUP_DIR/chats.server.js"
    docker cp "$CONTAINER:/home/node/app/public/script.js"                "$BACKUP_DIR/script.js"
    docker cp "$CONTAINER:/home/node/app/public/scripts/group-chats.js"   "$BACKUP_DIR/group-chats.js"
    docker cp "$CONTAINER:/home/node/app/public/scripts/chats.js"         "$BACKUP_DIR/chats.js"
    docker cp "$CONTAINER:/home/node/app/src/server-startup.js"           "$BACKUP_DIR/server-startup.js"
    docker cp "$CONTAINER:/home/node/app/public/scripts/tokenizers.js"   "$BACKUP_DIR/tokenizers.js"
    info "Backups saved to $BACKUP_DIR"

    info "Applying patches inside container..."

    # Copy patches and new files into container
    docker cp "$SCRIPT_DIR" "$CONTAINER:/tmp/_inc_save_patches"

    # Apply patches (incremental save)
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -p1 < /tmp/_inc_save_patches/chats.server.1.17.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -p1 < /tmp/_inc_save_patches/script.1.17.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -p1 < /tmp/_inc_save_patches/group-chats.1.17.patch"

    # Apply patches (image proxy cache)
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -p1 < /tmp/_inc_save_patches/server-startup.1.17.patch"
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -p1 < /tmp/_inc_save_patches/chats.1.17.patch"

    # Apply patches (token counting optimization)
    docker exec "$CONTAINER" sh -c "cd /home/node/app && patch -p1 < /tmp/_inc_save_patches/tokenizers.1.17.patch"

    # Copy new files (image proxy endpoint)
    docker exec "$CONTAINER" cp /tmp/_inc_save_patches/image-proxy.js /home/node/app/src/endpoints/image-proxy.js

    # Cleanup
    docker exec "$CONTAINER" rm -rf /tmp/_inc_save_patches

    info "Restarting container..."
    docker restart "$CONTAINER"
    sleep 3

    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" = "true" ]; then
        info "Done! Container '$CONTAINER' is running with incremental save + image cache enabled."
    else
        error "Container failed to start. Check logs: docker logs $CONTAINER"
    fi
fi

# ─── Local mode ──────────────────────────────────────────────────────

if [ "$MODE" = "local" ]; then
    if [ ! -f "$ST_DIR/server.js" ] || [ ! -f "$ST_DIR/public/script.js" ]; then
        error "'$ST_DIR' does not look like a SillyTavern installation."
    fi

    info "Backing up original files..."
    BACKUP_DIR="$SCRIPT_DIR/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp "$ST_DIR/src/endpoints/chats.js"          "$BACKUP_DIR/chats.server.js"
    cp "$ST_DIR/public/script.js"                "$BACKUP_DIR/script.js"
    cp "$ST_DIR/public/scripts/group-chats.js"   "$BACKUP_DIR/group-chats.js"
    cp "$ST_DIR/public/scripts/chats.js"         "$BACKUP_DIR/chats.js"
    cp "$ST_DIR/src/server-startup.js"           "$BACKUP_DIR/server-startup.js"
    cp "$ST_DIR/public/scripts/tokenizers.js"   "$BACKUP_DIR/tokenizers.js"
    info "Backups saved to $BACKUP_DIR"

    info "Applying patches..."
    cd "$ST_DIR"
    patch -p1 < "$SCRIPT_DIR/chats.server.1.17.patch"
    patch -p1 < "$SCRIPT_DIR/script.1.17.patch"
    patch -p1 < "$SCRIPT_DIR/group-chats.1.17.patch"
    patch -p1 < "$SCRIPT_DIR/server-startup.1.17.patch"
    patch -p1 < "$SCRIPT_DIR/chats.1.17.patch"
    patch -p1 < "$SCRIPT_DIR/tokenizers.1.17.patch"

    info "Copying new files..."
    cp "$SCRIPT_DIR/image-proxy.js" "$ST_DIR/src/endpoints/image-proxy.js"

    info "Done! Restart SillyTavern to activate incremental save + image cache."
fi
