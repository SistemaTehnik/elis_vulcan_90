#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Запуск стека
# Использование: ./scripts/07-start-stack.sh [--dir PATH] [--wait SECONDS]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INSTALL_DIR="${HOME}/elis_vulcan-90"
WAIT=25

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)  INSTALL_DIR="$2"; shift 2 ;;
        --wait) WAIT="$2"; shift 2 ;;
        *) die "Неизвестный аргумент: $1" ;;
    esac
done

require_non_root

cd "$INSTALL_DIR" || die "Не могу перейти в $INSTALL_DIR"

if [[ ! -f docker-compose.yml ]]; then
    die "docker-compose.yml не найден в $INSTALL_DIR"
fi

if ! is_docker_installed; then
    die "Docker не установлен. Запустите scripts/02-install-docker.sh"
fi

if ! docker ps >/dev/null 2>&1; then
    warn "Не могу подключиться к Docker без sudo."
    warn "Скорее всего, вы не в группе docker или не перелогинились."
    warn "Варианты:"
    warn "  1. Перелогиньтесь (logout/login)"
    warn "  2. Или запустите с sudo: sudo docker compose up -d"
    echo ""
    read -rp "Попробовать через sudo? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        step "Запуск через sudo"
        sudo docker compose up -d
        sleep "$WAIT"
        sudo docker compose ps
        exit 0
    else
        die "Прервано. Перелогиньтесь и повторите."
    fi
fi

step "Запуск ELIS_Vulcan-90"
docker compose up -d

log "Ожидание $WAIT секунд..."
sleep "$WAIT"

step "Статус контейнеров"
docker compose ps

echo ""
RUNNING=$(docker compose ps --status running --format json 2>/dev/null | wc -l)
TOTAL=$(docker compose ps --format json 2>/dev/null | wc -l)
success "Запущено: $RUNNING / $TOTAL"

if [[ "$RUNNING" -lt "$TOTAL" ]]; then
    error "═══════════════════════════════════════════════"
    error "  НЕ ВСЕ КОНТЕЙНЕРЫ ПОДНЯЛИСЬ: $RUNNING / $TOTAL"
    error "═══════════════════════════════════════════════"
    echo ""
    warn "Логи проблемных контейнеров:"
    for svc in $(docker compose ps --format "{{.Service}}" 2>/dev/null); do
        status=$(docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null || echo "unknown")
        if [[ "$status" != "running" ]]; then
            error "───── $svc ($status) ─────"
            docker compose logs "$svc" --tail=10 2>&1 | sed 's/^/  /'
            echo ""
        fi
    done
    die "Установка завершилась с ошибками. Проверьте логи выше."
fi

success "Все $TOTAL контейнеров успешно запущены!"

IP=$(get_server_ip)
echo ""
success "Доступ к сервисам:"
echo "  FUXA (SCADA):  http://${IP}:1881"
echo "  Draw.io:       http://${IP}:8080"
echo "  InfluxDB:      http://${IP}:8086"
echo "  Grafana:       http://${IP}:3000"
echo "  Node-RED:      http://${IP}:1880"
echo "  Apprise:       http://${IP}:8000"
echo "  Uptime Kuma:   http://${IP}:3001"
echo "  Portainer:     https://${IP}:9443"
