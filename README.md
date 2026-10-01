# ELIS_Vulcan-90

> **Электронная Логическая Интеллектуальная Система «Вулкан-90»**  
> SCADA для реального мира

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-29.x-blue.svg)](https://www.docker.com/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04_LTS-orange.svg)](https://ubuntu.com/)
[![Telegram](https://img.shields.io/badge/Telegram-@Zhu_ch_kov-blue.svg)](https://t.me/Zhu_ch_kov)

---

## 📖 О проекте

**ELIS_Vulcan-90** — современная высокотехнологичная SCADA-система нового поколения, разработанная для обеспечения сквозного контроля, аналитики и беспрецедентной надежности технологических процессов в реальном мире.

Реализуя концепцию **«от датчика до решений»**, система объединяет:
- Классические инструменты **HMI** (человеко-машинный интерфейс)
- Технологии **IIoT** (промышленный интернет вещей)
- Продвинутую **аналитику данных**
- Алгоритмы **автоматизации**

Архитектура построена на принципах **микросервисной контейнеризации**, гибкости, простоты развертывания и непрерывного развития.

---

## ✨ Возможности

| Возможность | Реализация |
|---|---|
| 📊 **Сбор данных** | Modbus RTU, MQTT, OPC UA |
| 💾 **Хранение истории** | InfluxDB (TSDB) + Telegraf |
| 🎨 **Визуализация** | FUXA (SCADA HMI) + Grafana |
| 🔔 **Уведомления** | Apprise (Telegram, Email, Slack) |
| ⚙️ **Автоматизация** | Node-RED (low-code) + Python |
| 📈 **Мониторинг** | Uptime Kuma |
| 🖥️ **Проектирование** | Draw.io (за Nginx с Basic Auth) |
| 🐳 **Управление** | Portainer + Docker Compose |

---

## 🏗️ Архитектура

Экосистема состоит из **12 изолированных Docker-контейнеров**, разделённых на 4 логических слоя:

```
┌─────────────────────────────────────────────────────────┐
│                    ELIS_Vulcan-90                       │
│                                                         │
│  Слой сбора данных:                                     │
│  ├── hmi-frontend (FUXA)    — SCADA HMI                 │
│  ├── mqtt-broker (Mosquitto) — MQTT-шина                │
│  └── logic-engine (Python)  — алгоритмы                 │
│                                                         │
│  Слой хранения:                                         │
│  ├── influxdb               — TSDB (история)            │
│  ├── telegraf               — MQTT → InfluxDB           │
│  └── grafana                — дашборды                  │
│                                                         │
│  Слой автоматизации:                                    │
│  ├── node-red               — low-code                  │
│  └── apprise                — уведомления               │
│                                                         │
│  Служебный слой:                                        │
│  ├── hmi-designer (Draw.io) — редактор схем             │
│  ├── nginx-auth             — защитный шлюз             │
│  ├── portainer              — управление Docker         │
│  └── uptime-kuma            — мониторинг                │
└─────────────────────────────────────────────────────────┘
```

---

## 🚀 Быстрый старт

### Требования

- **ОС:** Ubuntu Server 22.04 LTS (или новее)
- **CPU:** 4 ядра (рекомендовано)
- **RAM:** 16 ГБ (рекомендовано)
- **Диск:** 120 ГБ SSD (рекомендовано)
- **Сеть:** статический IP
- **USB:** для подключения PLC (опционально)

### Установка

```bash
# 1. Клонировать репозиторий
git clone https://github.com/SistemaTehnik/elis_vulcan_90.git
cd elis_vulcan_90

# 2. Запустить установщик
./install.sh
```

**Установщик автоматически:**
- Проверит систему
- Установит Docker
- Создаст структуру директорий
- Сгенерирует пароли и `.env`
- Настроит udev для PLC
- Создаст конфиги
- Запустит 12 контейнеров

**⏱️ Время установки:** 5–15 минут.

---

## 📋 Доступ к сервисам

После установки откройте в браузере:

| Сервис | URL | Логин |
|---|---|---|
| **FUXA** (SCADA) | `http://<IP>:1881` | `admin` / `123456` |
| **Grafana** | `http://<IP>:3000` | `admin` / (из `.secrets-*.txt`) |
| **InfluxDB** | `http://<IP>:8086` | `admin` / (из `.secrets-*.txt`) |
| **Draw.io** | `http://<IP>:8080` | `admin` / (из `.htpasswd-password`) |
| **Node-RED** | `http://<IP>:1880` | — |
| **Apprise** | `http://<IP>:8000` | — |
| **Uptime Kuma** | `http://<IP>:3001` | создать при входе |
| **Portainer** | `https://<IP>:9443` | создать при входе |

**⚠️ Пароли сохраняются в `~/elis_vulcan-90/.secrets-*.txt`. Сохраните их в менеджер паролей и удалите файл!**

---

## 📋 Управление

### Основные команды

```bash
cd ~/elis_vulcan-90

# Запуск всего стека
docker compose up -d

# Остановка
docker compose down

# Перезапуск одного сервиса
docker compose restart hmi-frontend

# Логи
docker compose logs -f hmi-frontend --tail=100

# Статус
docker compose ps
```

### Обновление

```bash
cd ~/elis_vulcan-90

# Бэкап перед обновлением
sudo tar -czf ~/backup-$(date +%F).tar.gz -C ~ elis_vulcan-90/

# Обновить образы
docker compose pull
docker compose up -d
```

### Бэкап

```bash
cd ~/elis_vulcan-90

# Полный бэкап (с sudo!)
sudo tar -czf ~/elis-vulcan-FULL-BACKUP-$(date +%Y%m%d-%H%M).tar.gz \
    -C ~ elis_vulcan-90/
sudo chown $USER:$USER ~/elis-vulcan-FULL-BACKUP-*.tar.gz

# Бэкап всех Docker-образов
docker save $(docker compose config --images | sort -u) \
    | gzip > ~/full-stack-$(date +%F).tar.gz
```

### Восстановление

```bash
# 1. Распаковать архив
tar -xzf backup.tar.gz -C ~

# 2. Восстановить права сервисов
cd ~/elis_vulcan-90
./scripts/restore.sh

# 3. Запустить
docker compose up -d
```

### Удаление

```bash
cd ~/elis_vulcan-90

# Мягкое — только контейнеры
./uninstall.sh --keep-data

# Полное — с директорией
sudo ./uninstall.sh
```

---

## 📁 Структура проекта

```
elis_vulcan-90/
├── docker-compose.yml          # Манифест всех 12 контейнеров
├── .env                        # Пароли и переменные (НЕ в git!)
├── .env.example                # Шаблон для git
├── install.sh                  # Мастер-установщик
├── uninstall.sh                # Мастер-удаления
├── scripts/                    # Модульные скрипты
│   ├── 01-check-system.sh
│   ├── 02-install-docker.sh
│   ├── 03-create-structure.sh
│   ├── 04-generate-secrets.sh
│   ├── 05-setup-udev.sh
│   ├── 06-create-configs.sh
│   ├── 07-start-stack.sh
│   ├── 08-change-password.sh
│   ├── backup.sh
│   └── restore.sh
├── services/                   # Данные всех сервисов
│   ├── hmi-frontend/           # FUXA
│   ├── mqtt-broker/            # Mosquitto
│   ├── logic-engine/           # Python-алгоритмы
│   ├── hmi-designer/           # Draw.io
│   ├── nginx/                  # Шлюз
│   ├── portainer/              # Управление Docker
│   ├── influxdb/               # TSDB
│   ├── grafana/                # Визуализация
│   ├── telegraf/               # Сборщик
│   ├── node-red/               # Автоматизация
│   ├── apprise/                # Уведомления
│   └── uptime-kuma/            # Мониторинг
├── backups/                    # Автобэкапы
└── docs/                       # Документация
```

---

## 🎯 Для кого этот проект

| Аудитория | Что получает |
|---|---|
| **Промышленные администраторы** | Готовый стек SCADA с автоматизацией |
| **Инженеры АСУ ТП** | Modbus RTU, MQTT, PLC-интеграция |
| **DevOps / SRE** | Микросервисная архитектура, Docker |
| **Студенты** | Реальный опыт работы с промышленной SCADA |
| **Научные лаборатории** | Готовая платформа для экспериментов |
| **Малый бизнес** | Недорогая SCADA без лицензий |
| **Open-source сообщество** | Модульный проект для контрибьютинга |

**Миссия проекта:** сделать промышленную автоматизацию **доступной** — для студентов, малого бизнеса, научных лабораторий и энтузиастов.

**Ценности:**
- 🌋 **Надежность** — работает в реальных условиях
- 🧠 **Интеллект** — интеграция с ML/AI
- ⚡ **Гибкость** — модульная архитектура
- 🔧 **Простота** — установка за вечер
- ♾️ **Развитие** — open-source

---

## 🛠️ Технологии

| Технология | Назначение |
|---|---|
| **Docker** | Контейнеризация |
| **Docker Compose** | Оркестрация 12 сервисов |
| **FUXA** | SCADA HMI |
| **InfluxDB** | База временных рядов |
| **Grafana** | Дашборды и аналитика |
| **Mosquitto** | MQTT-брокер |
| **Telegraf** | Сборщик данных |
| **Node-RED** | Low-code автоматизация |
| **Apprise** | Центр уведомлений |
| **Uptime Kuma** | Мониторинг |
| **Portainer** | Управление Docker |
| **Draw.io** | Редактор мнемосхем |
| **Python** | Прикладные алгоритмы |

---

## 📚 Документация

Полное **Руководство администратора** — в файле [`docs/ELIS_Vulcan-90_administrator_guide.pdf`](docs/).

Содержит:
- Архитектуру и состав системы
- Требования к серверу
- Пошаговую установку
- Резервное копирование и восстановление
- Мониторинг и диагностику
- Типовые неисправности
- Управление пользователями и безопасность

---

## 🤝 Как внести вклад

Мы приветствуем контрибьюторов!

**Как помочь:**
1. **Форкните** репозиторий
2. Создайте **ветку** для своей фичи (`git checkout -b feature/amazing-feature`)
3. **Закоммитьте** изменения (`git commit -m 'Add amazing feature'`)
4. **Запушьте** ветку (`git push origin feature/amazing-feature`)
5. Откройте **Pull Request**

**Что можно улучшить:**
- Добавить новые сервисы (OPC UA, TimescaleDB, Home Assistant)
- Улучшить скрипты установки
- Расширить документацию
- Перевести на другие языки
- Написать тесты

---

## 📜 Лицензия

Проект распространяется под лицензией **MIT**. См. файл [LICENSE](LICENSE).

Это означает, что вы можете:
- ✅ Использовать в коммерческих проектах
- ✅ Модифицировать
- ✅ Распространять
- ✅ Продавать

**Единственное требование** — сохранять упоминание авторства.

---

## 📞 Контакты

**Репозиторий:** https://github.com/SistemaTehnik/elis_vulcan_90  
**Документация:** [`docs/`](docs/)  
**Telegram:** [@Zhu_ch_kov](https://t.me/Zhu_ch_kov)

**По вопросам:**
- 🐛 **Багов и ошибок** — создайте [Issue](https://github.com/SistemaTehnik/elis_vulcan_90/issues)
- 💡 **Предложений и идей** — пишите в [Telegram](https://t.me/Zhu_ch_kov)
- 🔧 **Pull Request'ов** — приветствуются!

---

## ⭐ Поддержите проект

Если ELIS_Vulcan-90 оказался полезен:
- Поставьте **звезду** ⭐ на GitHub
- Расскажите коллегам
- Присоединяйтесь к разработке

---

<p align="center">
  <strong>ELIS_Vulcan-90</strong><br>
  <em>SCADA для реального мира</em><br>
  <br>
  Telegram: @Zhu_ch_kov
</p>
```

---