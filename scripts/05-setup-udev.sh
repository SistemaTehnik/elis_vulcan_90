#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Настройка udev-правил для PLC
# Использование: ./scripts/05-setup-udev.sh [--no-group]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

SKIP_GROUP=false
[[ "${1:-}" == "--no-group" ]] && SKIP_GROUP=true

require_non_root
require_sudo

step "Настройка udev-правил для PLC"

RULES_FILE="/etc/udev/rules.d/99-plc.rules"

sudo tee "$RULES_FILE" >/dev/null <<'EOF'
# ELIS_Vulcan-90 — правила для PLC
# Создаёт стабильный симлинк /dev/arduino для типовых USB-переходников

# Arduino Uno (оригинал, ATmega16U2)
SUBSYSTEM=="tty", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="0043", SYMLINK+="arduino", MODE="0660", GROUP="dialout"

# Клоны на CH340
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", SYMLINK+="arduino", MODE="0660", GROUP="dialout"

# Клоны на CP2102
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="arduino", MODE="0660", GROUP="dialout"

# Промышленные PLC на FTDI
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", SYMLINK+="arduino", MODE="0660", GROUP="dialout"
EOF
success "Правило записано в $RULES_FILE"

log "Перезагрузка udev-правил..."
sudo udevadm control --reload-rules
sudo udevadm trigger
success "udev-правила применены"

if [[ -e /dev/arduino ]]; then
    success "Симлинк /dev/arduino создан:"
    ls -l /dev/arduino
else
    warn "Симлинк /dev/arduino пока не создан (PLC не подключён)."
    warn "Он появится автоматически при подключении устройства."
fi

if [[ "$SKIP_GROUP" != "true" ]]; then
    if groups "$USER" | grep -qw dialout; then
        success "Пользователь $USER уже в группе dialout"
    else
        sudo usermod -aG dialout "$USER"
        warn "Пользователь $USER добавлен в группу dialout."
        warn "ТРЕБУЕТСЯ ПЕРЕЛОГИН (logout/login) для применения!"
    fi
fi

success "Настройка PLC завершена"
