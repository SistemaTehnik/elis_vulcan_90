#!/usr/bin/env bash
#
# ELIS_Vulcan-90 — Создание базовых конфигов
# Использование: ./scripts/06-create-configs.sh [--dir PATH]
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

step "Создание базовых конфигураций"

# ─── telegraf.conf ───
TELEGRAF_CONF="$INSTALL_DIR/services/telegraf/telegraf.conf"
if [[ -f "$TELEGRAF_CONF" ]]; then
    warn "telegraf.conf уже существует, пропускаем"
else
    cat > "$TELEGRAF_CONF" <<'EOF'
[agent]
  interval = "10s"
  flush_interval = "10s"

[[inputs.mqtt_consumer]]
  servers = ["tcp://mqtt-broker:1883"]
  topics = ["vulcan/#"]
  data_format = "json"
  name_override = "vulcan"

[[outputs.influxdb_v2]]
  urls = ["${INFLUXDB_URL}"]
  token = "${INFLUXDB_TOKEN}"
  organization = "${INFLUXDB_ORG}"
  bucket = "${INFLUXDB_BUCKET}"
EOF
    success "Создан telegraf.conf"
fi

# ─── mosquitto.conf ───
MOSQUITTO_CONF="$INSTALL_DIR/services/mqtt-broker/config/mosquitto.conf"
if [[ -f "$MOSQUITTO_CONF" ]]; then
    warn "mosquitto.conf уже существует, пропускаем"
else
    cat > "$MOSQUITTO_CONF" <<'EOF'
# ELIS_Vulcan-90 — конфигурация Mosquitto
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
EOF
    success "Создан mosquitto.conf"
fi

# ─── nginx default.conf ───
NGINX_CONF="$INSTALL_DIR/services/nginx/conf.d/default.conf"
if [[ -f "$NGINX_CONF" ]]; then
    warn "nginx default.conf уже существует, пропускаем"
else
    cat > "$NGINX_CONF" <<'EOF'
server {
    listen 80;
    server_name localhost;

    location / {
        auth_basic "ELIS Vulcan-90 — HMI Designer";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://hmi-designer:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
EOF
    success "Создан nginx default.conf"
fi

# ─── htpasswd (с автоустановкой apache2-utils) ───
HTPASSWD="$INSTALL_DIR/services/nginx/.htpasswd"

ensure_htpasswd() {
    if command -v htpasswd &>/dev/null; then
        return 0
    fi
    warn "htpasswd не найден — устанавливаем apache2-utils..."
    if ! command -v apt-get &>/dev/null; then
        die "htpasswd отсутствует, а apt-get недоступен. Установите apache2-utils вручную."
    fi
    require_sudo
    if ! sudo apt-get update -qq; then
        die "apt-get update завершился с ошибкой"
    fi
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2-utils; then
        die "Не удалось установить apache2-utils"
    fi
    if ! command -v htpasswd &>/dev/null; then
        die "apache2-utils установлен, но htpasswd всё ещё не найден в PATH"
    fi
    success "apache2-utils установлен"
}

ensure_htpasswd

if [[ -f "$HTPASSWD" ]]; then
    warn ".htpasswd уже существует, пропускаем"
else
    PASS=$(generate_password 20)
    htpasswd -cbB "$HTPASSWD" admin "$PASS" >/dev/null
    success ".htpasswd создан (логин: admin, пароль: $PASS)"
    echo "$PASS" > "$INSTALL_DIR/.htpasswd-password"
    chmod 600 "$INSTALL_DIR/.htpasswd-password"
fi

# ─── logic-engine/Dockerfile ───
DOCKERFILE="$INSTALL_DIR/services/logic-engine/Dockerfile"
if [[ ! -f "$DOCKERFILE" ]]; then
    cat > "$DOCKERFILE" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir paho-mqtt
COPY scripts/ /app/scripts/
CMD ["python", "-u", "/app/scripts/main.py"]
EOF
    success "Создан logic-engine/Dockerfile"
fi

# ─── logic-engine/scripts/main.py ───
MAIN_PY="$INSTALL_DIR/services/logic-engine/scripts/main.py"
if [[ ! -f "$MAIN_PY" ]]; then
    cat > "$MAIN_PY" <<'EOF'
#!/usr/bin/env python3
"""ELIS_Vulcan-90 — Logic Engine (заглушка)"""
import os, time
import paho.mqtt.client as mqtt

BROKER = os.getenv("MQTT_BROKER", "mqtt-broker")
PORT = int(os.getenv("MQTT_PORT", "1883"))

client = mqtt.Client()
client.connect(BROKER, PORT, 60)
print(f"[logic-engine] Подключён к MQTT {BROKER}:{PORT}", flush=True)

while True:
    client.publish("vulcan/heartbeat", int(time.time()))
    time.sleep(10)
EOF
    success "Создан logic-engine/scripts/main.py (заглушка)"
fi

success "Конфигурации созданы"
