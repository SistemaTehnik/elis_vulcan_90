#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Создание структуры директорий
# Использование: ./scripts/03-create-structure.sh [--dir PATH]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INSTALL_DIR="${HOME}/elis_vulcan-90"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) INSTALL_DIR="$2"; shift 2 ;;
        *) die "Неизвестный аргумент: $1" ;;
    esac
done

require_non_root

step "Создание структуры ELIS_Vulcan-90 в $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"/services/{hmi-frontend/{appdata,db,logs,images},mqtt-broker/{config,data,log},logic-engine/{scripts,logs},hmi-designer/projects,nginx/conf.d,portainer/data,influxdb/{data,config},grafana/{data,provisioning},telegraf,node-red/data,apprise/{config,attach},uptime-kuma/data}
mkdir -p "$INSTALL_DIR"/{backups,docs,scripts}

success "Структура создана:"
echo ""
cd "$INSTALL_DIR"
find . -maxdepth 3 -type d | sort | sed 's|^\./||; s|[^/]*/|  |g'
echo ""

log "Проверка прав:"
if [[ ! -w "$INSTALL_DIR" ]]; then
    die "Нет прав на запись в $INSTALL_DIR"
fi
success "Все директории доступны для записи"

# ─── Grafana работает под UID 472 — установить правильные права ───
if [[ -d "$INSTALL_DIR/services/grafana/data" ]]; then
    if command -v sudo &>/dev/null; then
        require_sudo
        sudo chown -R 472:472 "$INSTALL_DIR/services/grafana/data" 2>/dev/null || \
            warn "Не удалось изменить права на services/grafana/data (нет sudo?)"
        success "Права на services/grafana/data установлены (472:472)"
    fi
fi

log "Итоговая директория: $INSTALL_DIR"
