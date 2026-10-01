#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Создание бэкапа
# Использование: ./scripts/backup.sh [--dir PATH] [--output DIR]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$HOME/elis-vulcan-backups"
DATE=$(date +%Y%m%d-%H%M)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)    INSTALL_DIR="$2"; shift 2 ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        *) die "Неизвестный аргумент: $1" ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

step "Создание бэкапа ELIS_Vulcan-90"
log "Источник: $INSTALL_DIR"
log "Назначение: $OUTPUT_DIR"

require_sudo

# Остановить FUXA, чтобы БД была консистентной
log "Остановка FUXA и InfluxDB..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" stop hmi-frontend influxdb 2>/dev/null || true

# Создать архив
BACKUP_FILE="$OUTPUT_DIR/elis-vulcan-backup-${DATE}.tar.gz"
log "Создание архива..."
sudo tar -czf "$BACKUP_FILE" -C "$(dirname "$INSTALL_DIR")" "$(basename "$INSTALL_DIR")"
sudo chown "$USER:$USER" "$BACKUP_FILE"

# Запустить обратно
log "Запуск FUXA и InfluxDB..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" start hmi-frontend influxdb 2>/dev/null || true

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
success "Бэкап создан: $BACKUP_FILE ($SIZE)"
