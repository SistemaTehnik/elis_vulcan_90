#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Генерация паролей и .env файлов
# Использование: ./scripts/04-generate-secrets.sh [--dir PATH] [--force]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

INSTALL_DIR="${HOME}/elis_vulcan-90"
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)   INSTALL_DIR="$2"; shift 2 ;;
        --force) FORCE=true; shift ;;
        *) die "Неизвестный аргумент: $1" ;;
    esac
done

require_non_root

if [[ ! -d "$INSTALL_DIR/services" ]]; then
    die "Директория $INSTALL_DIR/services не найдена. Сначала запустите 03-create-structure.sh"
fi

step "Генерация секретов"

if [[ -f "$INSTALL_DIR/.env" ]] && [[ "$FORCE" != "true" ]]; then
    warn "Файл $INSTALL_DIR/.env уже существует."
    warn "Используйте --force для перезаписи (ВСЕ ПАРОЛИ БУДУТ ПОТЕРЯНЫ)."
    exit 0
fi

INFLUX_PASS=$(generate_password 24)
GRAFANA_PASS=$(generate_password 24)

# ─── Корневой .env (только теги и TZ) ───
cat > "$INSTALL_DIR/.env" <<EOF
# ELIS_Vulcan-90 — корневой .env
# Сгенерирован: $(date -Iseconds)
# ВНИМАНИЕ: этот файл не должен попадать в git!

TZ=Europe/Moscow

# Версии образов
FUXA_TAG=latest
MOSQUITTO_TAG=latest
INFLUXDB_TAG=2.7-alpine
GRAFANA_TAG=latest
TELEGRAF_TAG=latest
NODE_RED_TAG=latest
APPRISE_TAG=latest
UPTIME_KUMA_TAG=latest
PORTAINER_TAG=latest
DRAWIO_TAG=latest
NGINX_TAG=alpine
EOF
success "Создан $INSTALL_DIR/.env"

# ─── InfluxDB ───
cat > "$INSTALL_DIR/services/influxdb/.env" <<EOF
TZ=Europe/Moscow
DOCKER_INFLUXDB_INIT_MODE=setup
DOCKER_INFLUXDB_INIT_USERNAME=admin
DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUX_PASS}
DOCKER_INFLUXDB_INIT_ORG=elis_vulcan
DOCKER_INFLUXDB_INIT_BUCKET=scada_data
DOCKER_INFLUXDB_INIT_RETENTION=30d
EOF
success "Создан services/influxdb/.env"

# ─── Grafana ───
cat > "$INSTALL_DIR/services/grafana/.env" <<EOF
TZ=Europe/Moscow
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASS}
EOF
success "Создан services/grafana/.env"

# ─── Остальные сервисы (только TZ) ───
for svc in hmi-frontend mqtt-broker hmi-designer nginx node-red apprise uptime-kuma portainer; do
    echo "TZ=Europe/Moscow" > "$INSTALL_DIR/services/${svc}/.env"
done
success "Созданы .env для 8 сервисов"

# ─── logic-engine ───
cat > "$INSTALL_DIR/services/logic-engine/.env" <<EOF
TZ=Europe/Moscow
MQTT_BROKER=mqtt-broker
MQTT_PORT=1883
EOF
success "Создан services/logic-engine/.env"

# ─── Telegraf ───
cat > "$INSTALL_DIR/services/telegraf/.env" <<EOF
TZ=Europe/Moscow
INFLUXDB_URL=http://influxdb:8086
INFLUXDB_TOKEN=
INFLUXDB_ORG=elis_vulcan
INFLUXDB_BUCKET=scada_data
EOF
success "Создан services/telegraf/.env (токен добавите вручную)"

# ─── Сохраняем пароли ───
SECRETS_FILE="$INSTALL_DIR/.secrets-$(date +%Y%m%d).txt"
cat > "$SECRETS_FILE" <<EOF
ELIS_Vulcan-90 — Сгенерированные пароли
Дата: $(date -Iseconds)

InfluxDB  admin / $INFLUX_PASS
Grafana   admin / $GRAFANA_PASS
EOF
chmod 600 "$SECRETS_FILE"

echo ""
success "Пароли сохранены в: $SECRETS_FILE"
warn "СОХРАНИТЕ ИХ В НАДЁЖНОМ МЕСТЕ И УДАЛИТЕ ФАЙЛ!"
