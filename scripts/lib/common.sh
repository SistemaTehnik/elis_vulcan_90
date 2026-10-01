#!/usr/bin/env bash
# ELIS_Vulcan-90 — Общие функции для всех скриптов
# Подключается через: source "$(dirname "$0")/lib/common.sh"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

LOG_FILE="${LOG_FILE:-/tmp/elis-vulcan-$(date +%Y%m%d-%H%M%S).log}"

log()     { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[FAIL]${NC} $*" | tee -a "$LOG_FILE" >&2; }
step()    { echo -e "${CYAN}▶ $*${NC}" | tee -a "$LOG_FILE"; }
die()     { error "$*"; exit 1; }

require_non_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        die "Скрипт не должен запускаться от root. Используйте обычного пользователя с sudo."
    fi
}

require_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log "Требуется sudo. Возможно, будет запрошен пароль."
        sudo -v || die "sudo недоступен"
    fi
}

# Генерация пароля — читаем фиксированные 1024 байта, чтобы избежать SIGPIPE
generate_password() {
    local len="${1:-24}"
    head -c 1024 /dev/urandom | tr -dc 'A-Za-z0-9!@#%^&*' | head -c "$len"
}

get_server_ip() {
    hostname -I | awk '{print $1}'
}

is_docker_installed() {
    command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker 2>/dev/null
}

is_user_in_docker_group() {
    groups "$USER" 2>/dev/null | grep -qw docker
}
