#!/usr/bin/env bash
# ELIS_Vulcan-90 — Смена пароля сервиса
# Использование: ./scripts/08-change-password.sh <service>
# Пример: ./scripts/08-change-password.sh grafana

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

SERVICE="${1:-}"
[[ -z "$SERVICE" ]] && die "Укажите сервис: grafana | influxdb | fuxa | nginx"

case "$SERVICE" in
    grafana)
        warn "Grafana: смените пароль через UI → Profile → Change Password"
        warn "Затем обновите services/grafana/.env вручную"
        ;;
    influxdb)
        warn "InfluxDB: смените пароль через UI → Settings → Members"
        warn "Затем обновите services/influxdb/.env вручную"
        ;;
    nginx|drawio)
        read -rp "Новый пароль для admin: " -s NEWPASS; echo
        htpasswd -bB "$SCRIPT_DIR/../services/nginx/.htpasswd" admin "$NEWPASS"
        echo "$NEWPASS" > "$SCRIPT_DIR/../.htpasswd-password"
        chmod 600 "$SCRIPT_DIR/../.htpasswd-password"
        docker compose restart nginx-auth
        success "Пароль Draw.io обновлён"
        ;;
    fuxa)
        warn "FUXA: смените пароль через UI → Settings → Users"
        ;;
    *)
        die "Неизвестный сервис: $SERVICE"
        ;;
esac
