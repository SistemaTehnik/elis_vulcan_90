#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Проверка системы
# Использование: ./scripts/01-check-system.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_non_root

step "Проверка операционной системы"
if [[ ! -f /etc/os-release ]]; then
    die "/etc/os-release не найден — не удалось определить ОС"
fi
source /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    warn "Скрипт протестирован на Ubuntu/Debian. У вас: $ID $VERSION_ID"
    warn "Установка может не сработать. Продолжайте на свой риск."
else
    success "ОС: $PRETTY_NAME"
fi

step "Проверка архитектуры"
local_arch=$(uname -m)
case "$local_arch" in
    x86_64|aarch64) success "Архитектура: $local_arch" ;;
    *) warn "Неизвестная архитектура: $local_arch (может не сработать)" ;;
esac

step "Проверка sudo"
require_sudo
success "sudo доступен"

step "Проверка базовых утилит"
missing=()
for cmd in curl tar gzip sudo openssl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        success "  ✓ $cmd"
    else
        error "  ✗ $cmd — отсутствует"
        missing+=("$cmd")
    fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
    die "Отсутствуют обязательные утилиты: ${missing[*]}"
fi

step "Проверка свободного места в $HOME"
avail_kb=$(df -P "$HOME" | awk 'NR==2 {print $4}')
avail_gb=$((avail_kb / 1024 / 1024))
if [[ $avail_gb -lt 10 ]]; then
    die "Недостаточно места: ${avail_gb} ГБ. Нужно минимум 10 ГБ."
elif [[ $avail_gb -lt 20 ]]; then
    warn "Мало места: ${avail_gb} ГБ. Рекомендуется 20+ ГБ."
else
    success "Свободно: ${avail_gb} ГБ"
fi

step "Проверка uidmap (нужен для rootless Docker)"
if dpkg -l uidmap &>/dev/null; then
    success "uidmap установлен"
else
    warn "uidmap не установлен — не критично для rootful Docker"
fi

step "Проверка прав на /etc/udev/rules.d"
if [[ -w /etc/udev/rules.d/ ]]; then
    success "Есть права на запись udev-правил"
else
    warn "Нет прямых прав — потребуется sudo на этапе 05"
fi

success "Проверка системы завершена успешно"
echo ""
log "Лог: $LOG_FILE"
