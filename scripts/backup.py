#!/usr/bin/env python3
"""Consistent ELIS backups on the Linux Docker host; Python 3.8+, stdlib only."""

import argparse
import contextlib
import datetime as dt
import fnmatch
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import pwd
import shlex
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tarfile
import time
import urllib.request


class BackupError(Exception):
    pass


BANNER = """██▀██ ██    ▀██▀ ██▀██ ██ ██ ██ ██ ██    ██▀██ ██▀██ ███▄██ ██▀█▄ ██▀██ ██▀██ ██ ██ ██ ██ ██▀██
            ██▄   ██     ██  ██▄▄▄ ██ ██ ██ ██ ██    ██    ██▄██ ██ ▀██ ██▄█▀ ██▄██ ██    ██▄█▀ ██ ██ ██▄█▀
            █▓░▄▄ █▓░▄▄  █▓░ ▄▄ █▓ █▓░█▓ █▓░█▓ █▓░▄▄ █▓░▄▄ █▓░█▓ █▓░ █▓ █▓ █▓ █▓░█▓ █▓░▄▄ █▓░█▓ █▓░█▓ █▓░
            ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀ ▀▀▀▀▀  ▀▀▀  ▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀ ▀▀ ▀▀ ▀▀  ▀▀ ▀▀▀▀  ▀▀ ▀▀ ▀▀▀▀▀ ▀▀ ▀▀ ▀▀▀▀▀ ▀▀"""


def print_banner():
    if sys.stdout.isatty():
        print("\033[0;37m" + BANNER + "\033[0m", flush=True)
    else:
        print(BANNER, flush=True)
    print("ELIS Vulcan-90 — резервное копирование\n", flush=True)


def log(message):
    print(message, flush=True)


def docker(*args):
    result = subprocess.run(
        ["docker", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, check=False,
    )
    if result.returncode:
        # Docker errors can contain configuration secrets; do not echo stderr.
        raise BackupError("Ошибка Docker: " + shlex.join(["docker", *args])
                          + ". Код " + str(result.returncode))
    return result.stdout


def below(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def owner_home():
    return Path(pwd.getpwuid(int(os.environ.get("SUDO_UID", os.getuid()))).pw_dir)


def containers_for(root):
    endpoint = os.environ.get("DOCKER_HOST")
    if not endpoint:
        endpoint = json.loads(docker("context", "inspect", "--format",
                                     "{{json .Endpoints.docker.Host}}"))
    if not endpoint.startswith("unix://"):
        raise BackupError("Запускайте скрипт на самом сервере с локальным Docker socket.")
    ids = docker("ps", "--all", "--quiet", "--no-trunc", "--filter",
                 "label=com.docker.compose.project.working_dir=" + str(root)).split()
    if not ids:
        raise BackupError("Не найдены контейнеры Compose для " + str(root)
                          + ". Проверьте --project-dir и Docker context.")
    result = json.loads(docker("inspect", *ids))
    for item in result:
        state = item["State"]
        if state.get("Paused") or state.get("Restarting") or state.get("Status") in (
            "removing", "dead"
        ):
            raise BackupError("Нестабильное состояние контейнера " + item["Name"]
                              + "; сначала устраните его причину.")
    return result


def exclusions(relative):
    parts = relative.parts
    if any(part in (".git", "__pycache__", ".pytest_cache") for part in parts):
        return True
    if relative.name in (".DS_Store", "Thumbs.db"):
        return True
    if parts and parts[0] in ("backups", "elis-vulcan-backups"):
        return True
    if len(parts) == 1 and any(fnmatch.fnmatch(relative.name, pattern) for pattern in (
        "elis-vulcan-backup-*", "fuxa-backup-*.tar.gz", "fuxa-working-*.tar.gz"
    )):
        return True
    return False


def walk_entries(source, prefix, filtered=False):
    """No symlink traversal: store links, never recursively follow their targets."""
    def visit(path, relative):
        if relative.parts and filtered and exclusions(relative):
            return
        mode = path.lstat().st_mode
        if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode) or stat.S_ISLNK(mode)):
            raise BackupError("Необычный файл (socket/FIFO/device): " + str(path)
                              + ". Необходимо отдельно определить способ его сохранения.")
        yield path, str(Path(prefix) / relative)
        if stat.S_ISDIR(mode):
            with os.scandir(path) as stream:
                children = sorted(stream, key=lambda entry: entry.name)
            for entry in children:
                yield from visit(Path(entry.path), relative / entry.name)
    yield from visit(source, Path())


def roots_to_save(root, containers):
    roots = [(root, "project", True)]
    extras = {}
    for item in containers:
        for mount in item.get("Mounts", []):
            if mount["Type"] == "tmpfs":
                continue
            if mount["Type"] not in ("bind", "volume"):
                raise BackupError("Неизвестный тип Docker mount: " + mount["Type"])
            source = Path(mount["Source"]).resolve()
            if str(source) in ("/var/run/docker.sock", "/run/docker.sock"):
                continue
            if not source.exists():
                raise BackupError("Не найден источник Docker mount: " + str(source))
            if below(source, root):
                if exclusions(source.relative_to(root)):
                    raise BackupError("Данные контейнера попали в исключения: " + str(source))
                continue
            if below(root, source):
                raise BackupError("Слишком широкий mount включает весь проект: " + str(source))
            extras[str(source)] = mount["Type"]
    for index, (source, kind) in enumerate(sorted(extras.items()), 1):
        roots.append((Path(source), "external/{}-{:02d}".format(kind, index), False))
    rules = Path("/etc/udev/rules.d")
    if rules.is_dir() and str(rules.resolve()) not in extras:
        roots.append((rules, "host/udev-rules.d", False))
    return roots


def inventory(roots):
    total = count = 0
    for source, prefix, filtered in roots:
        for path, _ in walk_entries(source, prefix, filtered):
            info = path.lstat()
            count += 1
            if stat.S_ISREG(info.st_mode):
                # Check permissions before pausing the services.
                with path.open("rb"):
                    pass
                total += info.st_size
    return count, total


def add_bytes(archive, name, content):
    info = tarfile.TarInfo(name)
    info.size = len(content)
    info.mode = 0o600
    info.mtime = int(time.time())
    archive.addfile(info, io.BytesIO(content))


def build_archive(destination, roots, manifest, image_file=None):
    with tarfile.open(destination, "w:gz", compresslevel=1, dereference=False) as archive:
        for source, prefix, filtered in roots:
            for path, name in walk_entries(source, prefix, filtered):
                archive.add(path, arcname=name, recursive=False)
        if image_file:
            archive.add(image_file, arcname="docker/images.tar", recursive=False)
        add_bytes(archive, "backup-manifest.json",
                  json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8"))
    with destination.open("rb") as stream:
        os.fsync(stream.fileno())


def verify_archive(path):
    """Read every payload through gzip, checking truncation and CRC; no extraction."""
    members = 0
    with tarfile.open(path, "r:gz") as archive:
        for item in archive:
            members += 1
            if item.isfile():
                with archive.extractfile(item) as stream:
                    while stream.read(1024 * 1024):
                        pass
    # Also consume the gzip trailer if tarfile stopped at tar's end marker.
    import gzip
    with gzip.open(path, "rb") as stream:
        while stream.read(1024 * 1024):
            pass
    return members


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def service_name(item):
    labels = item.get("Config", {}).get("Labels") or {}
    return labels.get("com.docker.compose.service") or item["Name"].lstrip("/").replace("_", "-")


def stop_signal(item):
    configured = item.get("Config", {}).get("StopSignal")
    if configured and configured not in ("SIGTERM", "TERM", "15"):
        return None  # Respect an already customised stop signal.
    if service_name(item) in ("hmi-frontend", "logic-engine"):
        # FUXA 1.3.4 handles SIGINT; Python installs a SIGINT handler even as PID 1.
        return "SIGINT"
    return None


def stop_containers(containers, ids, timeout):
    selected = [item for item in containers if item["Id"] in ids]
    interactive = [item for item in selected if stop_signal(item) == "SIGINT"]
    remaining = [item for item in selected if item not in interactive]
    # Finish application writers while MQTT/InfluxDB are still available.
    for group, sig in ((interactive, "SIGINT"), (remaining, None)):
        if not group:
            continue
        names = ", ".join(item["Name"].lstrip("/") for item in group)
        log("Остановка {}: {}".format(sig or "штатным сигналом образа", names))
        command = ["stop", "--timeout", str(timeout)]
        if sig:
            command += ["--signal", sig]
        group_ids = [item["Id"] for item in group]
        docker(*command, *group_ids)
        states = json.loads(docker("inspect", *group_ids))
        if any(item["State"].get("Running") or item["State"].get("Restarting")
               or item["State"].get("Paused") or item["State"].get("OOMKilled")
               or item["State"].get("ExitCode") == 137 for item in states):
            raise BackupError("Не подтверждено штатное завершение: " + names)


def stop_report(work, states, timeout, command_error=None):
    """Preserve stop diagnostics before `docker start` resets the exit status."""
    records = []
    for item in states:
        state = item["State"]
        records.append({
            "name": item["Name"].lstrip("/"), "id": item["Id"],
            "running": bool(state.get("Running")),
            "restarting": bool(state.get("Restarting")),
            "paused": bool(state.get("Paused")),
            "exit_code": state.get("ExitCode"),
            "oom_killed": bool(state.get("OOMKilled")),
            "finished_at": state.get("FinishedAt"),
            "requested_stop_signal": stop_signal(item) or item.get("Config", {}).get("StopSignal") or "SIGTERM",
        })
    report = {
        "recorded_at": dt.datetime.now().astimezone().isoformat(),
        "stop_timeout_seconds": timeout,
        "stop_command_error": str(command_error) if command_error else None,
        "containers": records,
    }
    target = work / "stop-report.json"
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    log("Отчёт об остановке: " + str(target))
    problems = [record for record in records if record["oom_killed"] or record["exit_code"] == 137]
    for record in problems:
        log("Проблемный контейнер: {} | ExitCode={} | OOMKilled={}".format(
            record["name"], record["exit_code"], str(record["oom_killed"]).lower()))
    return problems


def startup_groups(containers):
    """Use actual Compose dependency labels; fall back to this project's known DAG."""
    defaults = {
        "hmi-frontend": {"mqtt-broker", "influxdb"},
        "logic-engine": {"mqtt-broker"},
        "telegraf": {"mqtt-broker", "influxdb"},
        "grafana": {"influxdb"}, "node-red": {"mqtt-broker"},
        "nginx-auth": {"hmi-designer"},
    }
    pending = {item["Id"]: item for item in containers}
    while pending:
        services = {service_name(item) for item in pending.values()}
        group = []
        for item in pending.values():
            labels = item.get("Config", {}).get("Labels") or {}
            declared = labels.get("com.docker.compose.depends_on")
            dependencies = ({part.split(":", 1)[0] for part in declared.split(",") if part}
                            if declared else defaults.get(service_name(item), set()))
            if not dependencies.intersection(services):
                group.append(item["Id"])
        if not group:
            # Recovery must still attempt every container, even with malformed labels.
            log("Не удалось упорядочить зависимости; пытаюсь запустить оставшиеся контейнеры.")
            group = list(pending)
        yield group
        for item_id in group:
            del pending[item_id]


def container_ready(item):
    state = item["State"]
    if (not state.get("Running") or state.get("Restarting")
            or state.get("Health", {}).get("Status", "healthy") != "healthy"):
        return False
    service = service_name(item)
    port = {"mqtt-broker": 1883, "influxdb": 8086}.get(service)
    if not port:
        return True
    bindings = item.get("NetworkSettings", {}).get("Ports", {}).get(str(port) + "/tcp") or []
    if not bindings:
        return True  # Docker health/running remains the only available readiness check.
    for binding in bindings:
        host = binding.get("HostIp") or "127.0.0.1"
        host = {"0.0.0.0": "127.0.0.1", "::": "::1"}.get(host, host)
        try:
            host_port = int(binding["HostPort"])
            if service == "mqtt-broker":
                with socket.create_connection((host, host_port), timeout=1):
                    return True
            else:
                address = "[{}]".format(host) if ":" in host else host
                url = "http://{}:{}/health".format(address, host_port)
                opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                with opener.open(url, timeout=1) as response:
                    if response.status == 200 and json.loads(response.read(65536)).get("status") == "pass":
                        return True
        except (OSError, ValueError):
            pass
    return False


def wait_ready(ids, deadline):
    while True:
        states = json.loads(docker("inspect", *ids))
        missing = [item["Name"].lstrip("/") for item in states if not container_ready(item)]
        if not missing or time.monotonic() >= deadline:
            return missing
        time.sleep(1)


def resume(ids, wait_seconds, snapshot=None):
    if not ids:
        return
    log("Запускаю ранее работавшие контейнеры...")
    with ignore_termination():
        # Try every ID even if one container cannot start.
        errors = []
        snapshot = snapshot or json.loads(docker("inspect", *ids))
        snapshot = [item for item in snapshot if item["Id"] in ids]
        deadline = time.monotonic() + wait_seconds
        for group in startup_groups(snapshot):
            for container in group:
                try:
                    docker("start", container)
                except BackupError as error:
                    errors.append(str(error))
            try:
                missing = wait_ready(group, deadline)
                if missing:
                    errors.append("Не дождались готовности: " + ", ".join(missing))
            except BackupError as error:
                errors.append(str(error))
        missing = wait_ready(ids, deadline)
        if missing:
            raise BackupError("Не подтверждён запуск/health: " + ", ".join(missing)
                              + (". " + "; ".join(errors) if errors else ""))
        log("Все ранее работавшие контейнеры снова запущены.")


@contextlib.contextmanager
def ignore_termination():
    old = {}
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        old[sig] = signal.signal(sig, signal.SIG_IGN)
    try:
        yield
    finally:
        for sig, handler in old.items():
            signal.signal(sig, handler)


def interrupted(signum, _frame):
    raise BackupError("Получен сигнал {}. Возвращаю сервисы в работу.".format(signum))


@contextlib.contextmanager
def project_lock(root, dry_run):
    if dry_run:
        yield
        return
    key = hashlib.sha256(str(root).encode()).hexdigest()[:16]
    lock_path = Path("/run/lock") / ("elis-backup-" + key + ".lock")
    fd = os.open(str(lock_path), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise BackupError("Для этого проекта уже выполняется бэкап.")
        yield


def make_backup(args):
    root = args.project_dir.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if not root.is_dir() or not (root / "docker-compose.yml").is_file():
        raise BackupError("В каталоге проекта не найден docker-compose.yml: " + str(root))
    if below(output, root):
        raise BackupError("Папка бэкапов должна быть вне проекта, например ~/elis-vulcan-backups.")
    if not shutil.which("docker"):
        raise BackupError("Docker не найден. Запускайте скрипт на сервере ELIS.")
    if not args.dry_run and (sys.platform != "linux" or os.geteuid() != 0):
        raise BackupError("Для бэкапа нужен Linux и sudo: часть файлов принадлежит root.")

    # A separate per-project flock does not change the files being archived.
    with project_lock(root, args.dry_run):
        containers = containers_for(root)
        running = [item["Id"] for item in containers if item["State"].get("Running")]
        if any(stop_signal(item) for item in containers):
            if "--signal" not in docker("stop", "--help"):
                raise BackupError("Для остановки FUXA через SIGINT нужен Docker CLI 23+ с docker stop --signal.")
        roots = roots_to_save(root, containers)
        if any(below(output, source.resolve()) for source, _, _ in roots):
            raise BackupError("Папка бэкапов находится внутри сохраняемых данных. Выберите другую --output.")
        count, size = inventory(roots)
        log("Проект: " + str(root))
        log("Назначение: " + str(output))
        log("Файлов и каталогов: {}; исходный объём: {:.1f} МиБ".format(count, size / 2**20))
        log("Будут временно остановлены: " + (", ".join(
            item["Name"].lstrip("/") for item in containers if item["Id"] in running
        ) or "нет работающих контейнеров"))
        for item in containers:
            if item["Id"] in running and stop_signal(item):
                log("Штатный сигнал {}: {}".format(item["Name"].lstrip("/"), stop_signal(item)))
        for source, prefix, _ in roots[1:]:
            log("Дополнительно: {} → {}".format(source, prefix))
        image_ids = sorted({item["Image"] for item in containers})
        image_size = 0
        if args.save_images:
            images = json.loads(docker("image", "inspect", *image_ids))
            image_size = sum(image["Size"] for image in images)
            log("Будут сохранены Docker-образы: {} (включая локальные сборки).".format(len(images)))
        if args.dry_run:
            log("Проверка завершена. Сервисы не останавливались, архив не создавался.")
            return

        output.mkdir(parents=True, exist_ok=True, mode=0o700)
        free = shutil.disk_usage(output).free
        needed = int((size + 2 * image_size) * 1.1) + 100 * 2**20
        if free < needed:
            raise BackupError("Недостаточно места: нужно с запасом {:.1f} ГиБ, свободно {:.1f} ГиБ."
                              .format(needed / 2**30, free / 2**30))
        stamp = dt.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S-%f")
        work = output / ("elis-vulcan-backup-" + stamp)
        work.mkdir(mode=0o700)
        archive = work / (work.name + ".tar.gz")
        partial = work / (archive.name + ".partial")
        image_file = work / "images.tar.partial" if args.save_images else None
        manifest = {
            "format_version": 1, "created": dt.datetime.now().astimezone().isoformat(),
            "source_project": str(root), "hostname": os.uname().nodename,
            "roots": [{"source": str(source), "archive_path": prefix}
                      for source, prefix, _ in roots],
            "exclusions": [".git", "__pycache__", ".pytest_cache", ".DS_Store", "Thumbs.db",
                           "backups/", "elis-vulcan-backups/", "root: elis-vulcan-backup-*",
                           "root: fuxa-backup-*.tar.gz", "root: fuxa-working-*.tar.gz"],
            "saved_docker_images": bool(args.save_images),
            "containers": containers,
            "notes": ["Symlinks are stored without following targets.",
                      "Container writable layers are not captured by docker image save.",
                      "Archive verification is not a tested application restore."],
        }
        (work / "backup-manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        # Export immutable images before the pause; retain image IDs in manifest.
        if image_file:
            log("Сохраняю Docker-образы (сервисы пока продолжают работать)...")
            docker("image", "save", "--output", str(image_file), *image_ids)
        log("Пауза сервисов: интерфейсы и запись измерений временно недоступны.")
        stopped_at = time.monotonic()
        try:
            if running:
                command_error = None
                try:
                    stop_containers(containers, running, args.stop_timeout)
                except BackupError as error:
                    command_error = error
                states = json.loads(docker("inspect", *running))
                problems = stop_report(work, states, args.stop_timeout, command_error)
                manifest["stop_report"] = {
                    "stop_timeout_seconds": args.stop_timeout,
                    "containers": [{"name": item["Name"], "state": item["State"]}
                                   for item in states],
                }
                (work / "backup-manifest.json").write_text(
                    json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
                if problems:
                    raise BackupError("Принудительное завершение: "
                                      + ", ".join(record["name"] for record in problems)
                                      + ". Согласованность базы не подтверждена, бэкап отменён. "
                                        "ExitCode=137 сам по себе не доказывает OOM; "
                                        "подробности в stop-report.json.")
                if command_error:
                    raise command_error
                if any(item["State"].get("Running") or item["State"].get("Restarting")
                       or item["State"].get("Paused") for item in states):
                    raise BackupError("Не все контейнеры остановились; копирование отменено.")
            manifest["paused_at"] = dt.datetime.now().astimezone().isoformat()
            (work / "backup-manifest.json").write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
            log("Создаю архив всех данных проекта...")
            build_archive(partial, roots, manifest, image_file)
        finally:
            try:
                resume(running, args.start_wait, containers)
            except BaseException:
                log("ВНИМАНИЕ: требуется проверить сервисы на сервере. Команда повторного запуска:")
                if running:
                    log(shlex.join(["docker", "start", *running]))
                raise
            log("Пауза с ожиданием запуска: {:.0f} сек.".format(time.monotonic() - stopped_at))
        # Verify after service recovery, so reading the archive adds no downtime.
        log("Проверяю чтение всего архива...")
        members = verify_archive(partial)
        digest = checksum(partial)
        sidecar = work / (archive.name + ".sha256")
        sidecar.write_text(digest + "  " + archive.name + "\n", encoding="ascii")
        partial.rename(archive)
        if image_file:
            image_file.unlink()
        if os.environ.get("SUDO_UID"):
            uid, gid = int(os.environ["SUDO_UID"]), int(os.environ["SUDO_GID"])
            for file in work.iterdir():
                os.chown(file, uid, gid)
            os.chown(work, uid, gid)
            # Make the default parent usable by the invoking account if newly root-created.
            if output.stat().st_uid == 0:
                os.chown(output, uid, gid)
        log("ГОТОВО: " + str(archive))
        log("Размер: {:.1f} МиБ; записей в архиве: {}".format(archive.stat().st_size / 2**20, members))
        log("SHA-256: " + digest)
        log("Старые бэкапы сохранены. Перенесите копию на другой компьютер/диск.")


def main(argv=None):
    print_banner()
    parser = argparse.ArgumentParser(description="Резервная копия ELIS Vulcan-90 на Linux-сервере.")
    parser.add_argument("--project-dir", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="Каталог проекта; по умолчанию родитель scripts/.")
    parser.add_argument("--output", type=Path, default=owner_home() / "elis-vulcan-backups",
                        help="Каталог бэкапов вне проекта.")
    parser.add_argument("--dry-run", action="store_true", help="Проверка без остановки и создания архива.")
    parser.add_argument("--save-images", action="store_true", help="Добавить используемые Docker-образы.")
    parser.add_argument("--stop-timeout", type=int, default=120, help="Время мягкой остановки, секунд.")
    parser.add_argument("--start-wait", type=int, default=60, help="Ожидание running/health, секунд.")
    args = parser.parse_args(argv)
    if args.stop_timeout < 1 or args.start_wait < 1:
        parser.error("Таймауты должны быть положительными.")
    os.umask(0o077)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupted)
    try:
        make_backup(args)
        return 0
    except (BackupError, OSError, ValueError, EOFError, tarfile.TarError) as error:
        log("ОШИБКА: " + str(error))
        log("Если появился файл .partial, он не является готовой резервной копией.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
