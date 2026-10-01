#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Установка Docker (rootful)
# Использование: ./scripts/02-install-docker.sh [--force]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

require_non_root
require_sudo

step "Установка Docker (rootful)"

if is_docker_installed && [[ "$FORCE" != "true" ]]; then
    success "Docker уже установлен и работает"
    docker --version
    docker compose version 2>/dev/null || warn "docker compose не найден"
    exit 0
fi

log "Скачивание и запуск официального установщика get.docker.com..."
curl -fsSL https://get.docker.com | sudo sh
success "Docker установлен"

log "Включение Docker в автозапуск..."
sudo systemctl enable --now docker
success "Docker запущен"

if is_user_in_docker_group; then
    success "Пользователь $USER уже в группе docker"
else
    sudo usermod -aG docker "$USER"
    warn "Пользователь $USER добавлен в группу docker."
    warn "⚠️  ТРЕБУЕТСЯ ПЕРЕЛОГИН (logout/login или reboot) для применения!"
    warn "После перелогина проверьте: docker ps (без sudo)"
fi

echo ""
log "Проверка версий:"
docker --version
docker compose version || warn "docker compose plugin не найден"
