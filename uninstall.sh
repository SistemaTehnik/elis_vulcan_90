#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Uninstaller
# Использование:
#   ./uninstall.sh                    # интерактивно
#   ./uninstall.sh --keep-data        # удалить контейнеры, сохранить данные
#   ./uninstall.sh --purge            # удалить всё без вопросов
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib/common.sh"

INSTALL_DIR="$SCRIPT_DIR"
KEEP_DATA=false
PURGE=false
REMOVE_IMAGES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-data)     KEEP_DATA=true ;;
        --purge)         PURGE=true; KEEP_DATA=false ;;
        --remove-images) REMOVE_IMAGES=true ;;
        --dir)           INSTALL_DIR="$2"; shift ;;
        --help|-h)
            cat <<EOF
ELIS_Vulcan-90 Uninstaller

Опции:
  --keep-data        Сохранить данные (services/)
  --purge            Удалить ВСЁ без вопросов
  --remove-images    Удалить Docker-образы проекта
  --dir PATH         Директория проекта
  --help, -h         Справка
EOF
            exit 0
            ;;
        *) die "Неизвестный аргумент: $1" ;;
    esac
    shift
done

echo -e "${RED}"
cat <<'BANNER'
╔═══════════════════════════════════════════════════╗
║   ELIS_Vulcan-90 — Удаление                       ║
╚═══════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

if [[ "$PURGE" != "true" ]] && [[ "$KEEP_DATA" != "true" ]]; then
    echo "⚠️  Это действие удалит ELIS_Vulcan-90."
    echo ""
    read -rp "Продолжить? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { log "Отменено"; exit 0; }
    read -rp "Вы ТОЧНО уверены? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { log "Отменено"; exit 0; }
fi

# ─── Контейнеры ───
if command -v docker >/dev/null 2>&1 && [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    step "Остановка и удаление контейнеров"
    cd "$INSTALL_DIR"
    docker compose down --remove-orphans 2>/dev/null || warn "docker compose down завершился с ошибкой"
fi

# ─── Образы ───
if [[ "$REMOVE_IMAGES" == "true" ]] && command -v docker >/dev/null 2>&1; then
    step "Удаление Docker-образов"
    images=$(cd "$INSTALL_DIR" && docker compose config --images 2>/dev/null || true)
    while IFS= read -r img; do
        [[ -z "$img" ]] && continue
        docker rmi "$img" 2>/dev/null || true
    done <<< "$images"
    docker rmi elis_vulcan-90-logic-engine 2>/dev/null || true
fi

# ─── Данные ───
if [[ "$KEEP_DATA" != "true" ]]; then
    step "Удаление данных"
    for dir in \
        services/hmi-frontend/appdata \
        services/hmi-frontend/db \
        services/hmi-frontend/logs \
        services/hmi-frontend/images \
        services/mqtt-broker/data \
        services/mqtt-broker/log \
        services/logic-engine/logs \
        services/hmi-designer/projects \
        services/portainer/data \
        services/influxdb/data \
        services/grafana/data \
        services/node-red/data \
        services/apprise/config \
        services/apprise/attach \
        services/uptime-kuma/data \
        backups; do
        [[ -d "$INSTALL_DIR/$dir" ]] && rm -rf "$INSTALL_DIR/$dir"
    done
    success "Данные удалены"
fi

# ─── Секреты ───
if [[ "$KEEP_DATA" != "true" ]]; then
    step "Удаление секретов"
    for f in .env .secrets-*.txt .htpasswd-password services/*/.env services/nginx/.htpasswd; do
        for file in $INSTALL_DIR/$f; do
            [[ -f "$file" ]] && shred -u "$file" 2>/dev/null || rm -f "$file"
        done
    done
    success "Секреты удалены"
fi

# ─── Директория проекта ───
if [[ "$KEEP_DATA" != "true" ]] && [[ -f "$INSTALL_DIR/install.sh" ]] && [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    step "Удаление директории проекта"
    cd "$HOME"
    rm -rf "$INSTALL_DIR"
    success "Директория $INSTALL_DIR удалена"
fi

echo ""
success "Удаление завершено"
