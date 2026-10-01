# SELFlab
<p align="center">
  <img src="https://github.com/user-attachments/assets/05150775-1cd6-4cd4-a24a-572384072031" width="720">
</p>
Конфіги та docker-compose стеки мого домашнього сервера. Тут те, що реально
крутиться 24/7 — медіа, бекапи фото, мережа, дрібні self-hosted утиліти.

## Стек

| Сервіс | Що робить | Порт (дефолт) |
|---|---|---|
| Jellyfin | медіасервер | 8096 |
| qBittorrent | торент-клієнт | 8080 |
| Navidrome | музичний стрімінг (Subsonic API) | 4533 |
| Immich | бекап і галерея фото з телефону | 2283 |
| Pi-hole + Knot Resolver | DNS-фільтрація реклами, свій рекурсивний резолвер | 80/443 |
| Tailscale | VPN / exit node для доступу ззовні | — |
| Stirling PDF | робота з PDF (мердж, OCR, конвертація) | 3010 |
| Vaultwarden | менеджер паролів (Bitwarden-сумісний) | 8192 |
| Uptime Kuma | моніторинг доступності сервісів | 3001 |
| Homepage | дашборд усіх сервісів | 3002 |
| Glances | агент системного моніторингу для дашборду (REST API, без UI) | 61208 (внутрішній) |
| Kopia | бекап конфігів у Cloudflare R2 | 51515 |
| SearXNG | метапошук | 8081 |
| Caddy | HTTPS-проксі з внутрішнім CA (`https://<сервіс>.home:8443`) | 8443 |

Всі порти, шляхи і основні налаштування задаються через env — порт у таблиці
просто дефолт, його можна змінити в `.env`.

## Структура

```
SELFlab/
├── docker/
│   ├── media/          # jellyfin, qbittorrent, navidrome
│   ├── immich/         # фото-бекап
│   ├── network/        # pihole, knot-resolver, tailscale
│   ├── translate/      # stirling-pdf
│   └── admin/          # vaultwarden, uptime-kuma, kopia, caddy, glances, searxng
│       └── homepage/   # конфіг дашборду (yaml + custom.css)
├── scripts/
│   └── db-backup.sh    # нічний стоп-кадр БД для Kopia (крон на сервері)
└── .gitignore
```

Кожна папка в `docker/` — окремий стек із власним `docker-compose.yml` і
`.env.example`. Копіюй `.env.example` у `.env` і заповнюй своїми значеннями
(шляхи, порти, секрети). Сам `.env` в git не потрапляє (див. `.gitignore`).

### Що задається через env

- **Шляхи** — усі host-шляхи в `volumes` (`JELLYFIN_CONFIG`, `STORAGE_DIR`,
  `IMMICH_UPLOAD`, `PIHOLE_ETC` і т.д.)
- **Порти** — публічні порти кожного сервісу (`JELLYFIN_PORT`, `WEBUI_PORT`,
  `IMMICH_PORT`, `PIHOLE_HTTP_PORT` і т.д.)
- **Користувач/група** — `PUID` / `PGID` (має збігатися з власником шляхів
  на хості, інакше контейнери не зможуть писати у волюми)
- **Мережа** — `TZ`, hostname/domainname, `TS_EXTRA_ARGS` (exit node,
  `192.168.1.0/24`), `TS_AUTHKEY`, паролі, версії образів; `LAN_IP` —
  локальна IP сервера (extra_hosts контейнерів, allowed hosts homepage)

Усі змінні мають дефолти через `${VAR:-...}` прямо в compose — навіть без
`.env` стек піднімається, просто з моїми значеннями.

## Бекап конфігів

`docker/admin` бекапить конфіги всіх стеків у Cloudflare R2 (S3, нативно)
через Kopia. Тільки налаштування — фото, музика і торенти не входять.
Старий gdrive-репозиторій через rclone лишений архівом
(`repository.config.gdrive.bak` + rclone.conf на сервері).

Разова підготовка на сервері:

1. Бакет `kopia` в R2 + Account API token (Object Read & Write на бакет)
2. Створити репозиторій (ендпоінт голим хостом, без шляху і без слеша в кінці):

   ```bash
   docker exec kopia kopia --config-file=/app/config/repository.config \
     repository create s3 --bucket=kopia \
     --endpoint=<ACCOUNT_ID>.r2.cloudflarestorage.com --region=auto \
     --access-key=<AK> --secret-access-key=<SK>
   ```

3. Глобальна політика (10 latest + 7 денних + 4 тижневих + 12 місячних +
   3 річних, авто-бекап о 02:00; БД-шляхи тільки вручну — див. нижче):

   ```bash
   docker exec kopia kopia --config-file=/app/config/repository.config \
     policy set --global --keep-latest=10 --keep-hourly=0 --keep-daily=7 \
     --keep-weekly=4 --keep-monthly=12 --keep-annual=3 \
     --snapshot-time=02:00 --compression=zstd
   # БД тільки вручну (стопнуті скриптом), авто о 02:00 їх не чіпає:
   for s in vaultwarden psnself selfwishes selfbase-garage-data \
     selfbase-garage-meta selfbase-spacetimedb-data selfbase-spacetimedb-config; do
     docker exec kopia kopia --config-file=/app/config/repository.config \
       policy set /sources/$s --manual
   done
   ```

   Джерела зараз (9): `vaultwarden`, `homepage`, `searxng` (з цього репо) +
   `psnself`, `selfwishes` і 4 волюми `selfbase-*` (зовнішні стеки,
   в kopia змонтовані як external volumes).

### Паролі (два різні!)

- `KOPIA_PASSWORD` — ключ шифрування репозиторію. Вводиться один раз при
  створенні репо, далі підставляється автоматично.
- `KOPIA_SERVER_PASSWORD` — пароль входу у веб-UI/API (`https://kopia.home:8443`).
  Міняється в Dockhand → env → Deploy (не забути перелогінитись в UI).

### Нічний бекап БД (стоп-кадр)

Файловий бекап живої БД може бути рваним, тому БД бекапляться зупиненими
скриптом `/home/trip/db-backup.sh` (джерело в репо: `scripts/db-backup.sh`)
по крону о 01:55 (стоп 6 контейнерів →
`snapshot create` 7 шляхів → старт; авто о 02:00 для цих шляхів вимкнене
через `policy set --manual`). Плоскі `homepage`/`searxng` стопати не треба —
їх бере авто о 02:00.

```bash
# вручну так само:
/home/trip/db-backup.sh
docker exec kopia kopia --config-file=/app/config/repository.config \
  snapshot create /sources/homepage /sources/searxng
# перевірка:
docker exec kopia kopia --config-file=/app/config/repository.config \
  snapshot list | grep -E 'sources/'
```

Контейнери БД: `selfbase-web`, `selfbase-garage`, `selfbase-spacetimedb`,
`vaultwarden`, `selfwishes`, `psnself`.

### Граблі (якщо колись щось упаде)

- **Було на rclone+gdrive (до 01.10.2026)**: rclone-конфіг монтувався `:ro`,
  Kopia падала з `unable to start rclone: timed out`, лікувалось тільки CLI і
  `--rclone-startup-timeout=180s`. Після переїзду на нативний S3 (R2) неактуально
- **Endpoint R2**: голий хост `<ACCOUNT_ID>.r2.cloudflarestorage.com` — без
  схеми з шляхом, без імені бакета і без слеша в кінці, інакше
  `Endpoint url cannot have fully qualified paths`. Бакет тільки в `--bucket`
- **Абсолютні шляхи в UI**: відносний шлях склеюється з домашнім каталогом
  і падає з "path does not exist"
- **`Failed to save config after 10 tries`** в логах — безпечний шум від
  `:ro` маунта rclone.conf, на роботу не впливає
- rclone у цьому образі лежить у `/usr/bin/rclone` (не в PATH контейнера)
- Монітор Kopia в Uptime Kuma: приймати коди `200-299,401` — Kopia віддає
  логін-сторінку з кодом 401 (браузер її рендерить, чекер — ні)
- CLI-снапшот не з'являється в UI одразу (сервер не бачить змін іншого
  процесу): вкладка Snapshots → кнопка синхронізації, або `docker restart kopia`
- **Caddy не піднімається** (`mount src=...Caddyfile ... not a directory`):
  docker створює відсутній host-шлях bind-mount як директорію. Перевір:
  `docker compose config | grep -A3 Caddyfile` — source має бути
  `/home/trip/caddy/Caddyfile` (файл), а не `/home/trip/caddy` (папка) —
  якщо папка, виправ `CADDY_CONFIG` у `.env`/Dockhand; якщо шлях правильний,
  а файл зник — `rmdir /home/trip/caddy/Caddyfile` і скопіюй файл з репо

## Доступ до сервісів (HTTPS через Caddy)

Bitwarden-клієнти та веб-сховище вимагають HTTPS, тому перед сервісами стоїть
Caddy з власним внутрішнім CA. Усі сервіси з веб-сторінкою доступні як
`https://<ім'я>.home:8443`:

`vault.home` (8192), `jellyfin.home` (8096), `qbittorrent.home` (8080),
`navidrome.home` (4533), `immich.home` (2283), `stirling.home` (3010),
`kuma.home` (3001), `kopia.home` (51515),
`homepage.home` (3002).

- **Вдома** — просто відкриваєш адресу, tailscale не потрібен. Один раз
  встанови CA-сертифікат Caddy на пристрій:
  `docker compose exec caddy cat /data/caddy/pki/authorities/local/root.crt`
  → Android: Налаштування → Безпека → Встановити сертифікат → CA
- **Поза домом** — увімкни tailscale на телефоні. У Tailscale admin console
  (DNS → Nameservers → Custom → tailnet IP сервера + Override local DNS)
  налаштований pihole як DNS, тож `.home` імена резолвляться і трафік іде через
  маршрут `192.168.1.0/24`
- У Pi-hole має бути Local DNS record для кожного імені → LAN IP сервера.
  Перевірити всі одразу:

  ```bash
  for h in vault jellyfin qbittorrent navidrome immich stirling kuma kopia homepage; do
    r=$(dig @192.168.1.110 "$h.home" +short)
    [ -z "$r" ] && echo "MISSING: $h.home" || echo "OK: $h.home -> $r"
  done
  ```

- Uptime Kuma довіряє внутрішньому CA через `NODE_EXTRA_CA_CERTS` + маунт
  `root.crt` (див. `docker/admin/docker-compose.yml`)
- qBittorrent: у Web UI → Налаштування → Веб-інтерфейс вимкни
  **Host header validation**, інакше віддаватиме помилку через проксі
- Прямий доступ по старих адресах (`http://jellyfin.home:8096`) лишається
- Якщо на хості увімкнений ufw з `default deny incoming` — він ріже і трафік
  з docker-моста на опубліковані порти, і Caddy віддає `502 dial i/o timeout`
  (docker-proxy зовні живий, але пакети з підмережі контейнерів не доходять).
  Один раз дозволити підмережу адмін-мережі:

  ```bash
  NET=$(docker inspect caddy -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
  SUBNET=$(docker network inspect "$NET" -f '{{(index .IPAM.Config 0).Subnet}}')
  # порти всіх сервісів, які Caddy проксіює (див. Caddyfile)
  sudo ufw allow from "$SUBNET" to any port 8192,8096,8080,4533,2283,3010,3001,3002,51515 proto tcp
  ```

## Дашборд Homepage

`https://homepage.home:8443` — головний екран із усіма сервісами.

- Конфіг: `docker/admin/homepage/` (`settings.yaml`, `services.yaml`,
  `widgets.yaml`, `bookmarks.yaml`, `custom.css`) → копіюється на сервер у
  `HOMEPAGE_CONFIG` (`/home/trip/homepage`) і бекапиться в Kopia (джерело `/sources/homepage`)
- Секрети віджетів не в репо: заповнюються в Dockhand (Env) як `HOMEPAGE_VAR_*`
  (jellyfin key, qbittorrent login, pihole token, tailscale key+tailnet+deviceid, immich key)
- Статус контейнерів — через Uptime Kuma
- Системний моніторинг хоста (CPU, RAM, температура, аптайм, диски) — віджет
  `glances` у `widgets.yaml`; дані тягне з контейнера `glances`
  (`GLANCES_OPT=-w --disable-webui` — тільки REST API, без власного веб-UI).
  Диски хоста видно через bind-mount: `/` → `/mnt/root`, `/mnt/ssd` → `/mnt/ssd`
  (віджет дивиться на ці шляхи в контейнері)
- Після зміни конфігу: онови сторінку (конфіги читаються гаряче).
  Рестарт/Deploy потрібен тільки після зміни env-змінних у Dockhand

## Запуск стеку

### Вручну

```bash
cd docker/media
cp .env.example .env
# заповнити .env
docker compose up -d
```

### Через Dockhand

Керую всім цим через [Dockhand](https://github.com/Finsys/dockhand) — там усе тягнеться
прямо з цього репо, без ручного `git pull` на сервері.

1. **Git Integration** → додати репозиторій у Dockhand. Форк необов'язковий:
   - **без форка** — вказуєш цей репо напряму і вписуєш свої значення (шляхи,
     порти, `TS_EXTRA_ARGS`, PUID/PGID, секрети) в UI стеку — вони перекривають
     дефолти з compose, тож нічого комітити не треба;
   - **з форком** — якщо хочеш ще й міняти самі compose-файли чи дефолтні
     значення у `.env.example` (свої шляхи замість `/home/trip/...`).
2. Створити окремий **git-стек на кожну підпапку** — кожен стек вказує на свій `compose path`:
   - `docker/media`
   - `docker/immich`
   - `docker/network`
   - `docker/translate`
   - `docker/admin`

   Dockhand відстежує кожну підпапку окремо і синкає тільки той стек,
   у чиїй директорії щось змінилось — інші стеки при цьому не чіпає.
3. **Env-змінні не через `.env` файл** — вписати значення з відповідного
   `.env.example` прямо в UI стеку (Compose editor → env variables). Секрети
   так взагалі не потрапляють у файлову систему репо, зберігаються в базі Dockhand.

## Нотатки

- Усі host-шляхи, порти, PUID/PGID і TZ задаються через env (див. `.env.example`
  кожної підпапки) — заміни `JELLYFIN_CONFIG`, `STORAGE_DIR`, `WEBUI_PORT` і т.д.
  на свої, і стек підніметься на твоїх шляхах без правки compose-файлів.
- Pi-hole працює як DNS + DHCP-фільтр на весь домашній LAN, Knot Resolver —
  рекурсивний резолвер, щоб не ходити до чужих DNS-серверів.
- Tailscale підіймає exit node, тому весь трафік з телефону/ноута може йти
  через домашню мережу коли я не вдома.
- IP-діапазон `192.168.1.0/24` в `TS_EXTRA_ARGS` — стандартна приватна
  підмережа, не унікальна інформація, але заміни якщо у тебе інша.

