#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Мастер-установщик
# Использование:
#   ./install.sh                    # всё по порядку
#   ./install.sh --skip-docker      # пропустить установку Docker
#   ./install.sh --only 03 04       # только этапы 03 и 04
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib/common.sh"

INSTALL_DIR="${HOME}/elis_vulcan-90"
SKIP_DOCKER=false
SKIP_UDEV=false
SKIP_START=false
ONLY_STEPS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)          INSTALL_DIR="$2"; shift 2 ;;
        --skip-docker)  SKIP_DOCKER=true; shift ;;
        --skip-udev)    SKIP_UDEV=true; shift ;;
        --skip-start)   SKIP_START=true; shift ;;
        --only)         shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do ONLY_STEPS+=("$1"); shift; done ;;
        --help|-h)
            cat <<EOF
ELIS_Vulcan-90 Installer

Опции:
  --dir PATH       Директория установки (по умолчанию: ~/elis_vulcan-90)
  --skip-docker    Не устанавливать Docker
  --skip-udev      Не настраивать udev
  --skip-start     Не запускать стек
  --only NN [NN]   Выполнить только указанные этапы (01,02,...)

Этапы:
  01  Проверка системы
  02  Установка Docker
  03  Создание структуры
  04  Генерация секретов
  05  Настройка udev для PLC
  06  Создание конфигов
  07  Запуск стека
EOF
            exit 0
            ;;
        *) die "Неизвестный аргумент: $1" ;;
    esac
done

require_non_root

if [[ ! -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    die "docker-compose.yml не найден в $SCRIPT_DIR. Проверьте структуру проекта."
fi

echo -e "${BLUE}"
cat <<'BANNER'
╔═══════════════════════════════════════════════════╗
║   ELIS_Vulcan-90 — SCADA для реального мира       ║
║   Установщик                                      ║
╚═══════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

log "Директория: $INSTALL_DIR"
log "Лог: $LOG_FILE"
echo ""

run_step() {
    local num="$1"
    local name="$2"
    local skip="${3:-false}"

    if [[ ${#ONLY_STEPS[@]} -gt 0 ]] && [[ ! " ${ONLY_STEPS[*]} " =~ " $num " ]]; then
        return 0
    fi

    if [[ "$skip" == "true" ]]; then
        warn "Этап $num ($name) — пропущен по флагу"
        return 0
    fi

    step "════ Этап $num: $name ════"
    local script
    script=$(ls "$SCRIPT_DIR/scripts/${num}-"*.sh 2>/dev/null | head -1)
    if [[ -z "$script" ]]; then
        die "Скрипт этапа $num не найден в $SCRIPT_DIR/scripts/"
    fi
    bash "$script" --dir "$INSTALL_DIR" || die "Этап $num провален"
}

run_step 01 "Проверка системы"
run_step 02 "Установка Docker"       "$SKIP_DOCKER"
run_step 03 "Создание структуры"
run_step 04 "Генерация секретов"
run_step 05 "Настройка udev для PLC" "$SKIP_UDEV"
run_step 06 "Создание конфигов"
run_step 07 "Запуск стека"           "$SKIP_START"

IP=$(get_server_ip)
echo ""
success "═══════════════════════════════════════════════════"
success "  ELIS_Vulcan-90 — Установка завершена!"
success "═══════════════════════════════════════════════════"
echo ""
echo "  Установочная директория: $INSTALL_DIR"
echo "  Лог установки:           $LOG_FILE"
echo ""
echo "  ─── Доступ к сервисам ───"
echo "  FUXA (SCADA):  http://${IP}:1881"
echo "  Draw.io:       http://${IP}:8080"
echo "  InfluxDB:      http://${IP}:8086"
echo "  Grafana:       http://${IP}:3000"
echo "  Node-RED:      http://${IP}:1880"
echo "  Apprise:       http://${IP}:8000"
echo "  Uptime Kuma:   http://${IP}:3001"
echo "  Portainer:     https://${IP}:9443"
echo ""
warn "Если вы только что установили Docker — перелогиньтесь для применения группы docker"
