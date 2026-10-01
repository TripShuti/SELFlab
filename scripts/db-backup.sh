#!/bin/bash
# Нічний стоп-кадр БД для Kopia.
# Стопає контейнери-БД, робить snapshot вже тихих файлів, піднімає назад.
# trap гарантує `docker start` навіть якщо snapshot впаде.
#
# Встановлення на сервер:
#   cp scripts/db-backup.sh /home/trip/db-backup.sh
#   chmod +x /home/trip/db-backup.sh
#   crontab -e
#   55 1 * * * /home/trip/db-backup.sh >>/home/trip/kopia/logs/db-backup.log 2>&1
#
# Для цих 7 шляхів в Kopia виставлено `policy set --manual`,
# авто-снапшот о 02:00 їх не чіпає (див. README "Бекап конфігів").
set -e
DBS="selfbase-web selfbase-garage selfbase-spacetimedb vaultwarden selfwishes psnself"
docker stop $DBS
trap "docker start $DBS" EXIT
docker exec kopia kopia --config-file=/app/config/repository.config snapshot create \
  /sources/vaultwarden /sources/psnself /sources/selfwishes \
  /sources/selfbase-garage-data /sources/selfbase-garage-meta \
  /sources/selfbase-spacetimedb-data /sources/selfbase-spacetimedb-config
docker start $DBS
trap - EXIT
