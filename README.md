# SELFlab

Конфіги та docker-compose стеки мого домашнього сервера. Тут те, що реально
крутиться 24/7 — медіа, бекапи фото, мережа, дрібні self-hosted утиліти.

## Стек

| Сервіс | Що робить | Порт (дефолт) |
|---|---|---|
| Jellyfin | медіасервер | 8096 |
| qBittorrent | торент-клієнт | 8080 |
| Navidrome | музичний стрімінг (Subsonic API) | 4533 |
| Immich | бекап і галерея фото з телефону | 2283 |
| Pi-hole + Unbound | DNS-фільтрація реклами, свій рекурсивний резолвер | 80/443 |
| Tailscale | VPN / exit node для доступу ззовні | — |
| Stirling PDF | робота з PDF (мердж, OCR, конвертація) | 3010 |
| LibreTranslate | self-hosted переклад тексту | 3020 |
| Vaultwarden | менеджер паролів (Bitwarden-сумісний) | 8192 |
| Uptime Kuma | моніторинг доступності сервісів | 3001 |
| Homepage | дашборд усіх сервісів | 3002 |
| Kopia | бекап конфігів у Google Drive | 51515 |
| Caddy | HTTPS-проксі з внутрішнім CA (`https://<сервіс>.home:8443`) | 8443 |

Всі порти, шляхи і основні налаштування задаються через env — порт у таблиці
просто дефолт, його можна змінити в `.env`.

## Структура

```
homelab/
├── docker/
│   ├── media/          # jellyfin, qbittorrent, navidrome
│   ├── immich/          # фото-бекап
│   ├── network/         # pihole, tailscale
│   ├── translate/       # stirling-pdf, libretranslate
│   └── admin/           # vaultwarden, uptime-kuma, kopia, caddy
└── .gitignore
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
  `192.168.1.0/24`), `TS_AUTHKEY`, паролі, версії образів

Усі змінні мають дефолти через `${VAR:-...}` прямо в compose — навіть без
`.env` стек піднімається, просто з моїми значеннями.

## Бекап конфігів

`docker/admin` бекапить конфіги всіх стеків (jellyfin, qbittorrent, navidrome,
pihole, tailscale, stirling, vaultwarden, uptime-kuma, homepage) у Google Drive
через Kopia + rclone. Тільки налаштування — фото, музика і торенти не входять.

Разова підготовка на сервері:

1. `rclone config --config /home/trip/kopia/rclone.conf` → remote `gdrive`
   (OAuth через браузер, client_id лишити порожнім — внутрішній ключ rclone
   для конфігів цілком тягне)
2. Перевірка: `rclone lsd --config /home/trip/kopia/rclone.conf gdrive:`
3. Створити репозиторій у CLI (UI-флоу не працює — див. «Граблі» нижче):

   ```bash
   docker exec kopia kopia --config-file=/app/config/repository.config \
     repository create rclone --remote-path=gdrive:kopia \
     --rclone-exe=/usr/bin/rclone --rclone-startup-timeout=180s
   ```

4. Глобальна політика (10 latest + 30 денних + 12 місячних, авто-бекап о 02:00):

   ```bash
   docker exec kopia kopia --config-file=/app/config/repository.config \
     policy set --global --keep-latest=10 --keep-hourly=0 --keep-daily=30 \
     --keep-weekly=0 --keep-monthly=12 --keep-annual=0 \
     --snapshot-time=02:00 --compression=zstd
   ```

### Паролі (два різні!)

- `KOPIA_PASSWORD` — ключ шифрування репозиторію. Вводиться один раз при
  створенні репо, далі підставляється автоматично.
- `KOPIA_SERVER_PASSWORD` — пароль входу у веб-UI/API (`https://kopia.home:8443`).
  Міняється в Dockhand → env → Deploy (не забути перелогінитись в UI).

### Ручний бекап

```bash
docker exec -d kopia bash -c \
  'kopia --config-file=/app/config/repository.config snapshot create --progress \
    /sources/qbittorrent /sources/navidrome /sources/pihole /sources/dnsmasq \
    /sources/tailscale /sources/stirling /sources/uptime-kuma /sources/jellyfin \
    /sources/homepage \
    > /tmp/backup.log 2>&1'
# прогрес:
docker exec kopia tail -f /tmp/backup.log
```

Перший снапшот jellyfin (~620 МБ) іде довше за годину — Google троттлить
великі заливи. Поки `snapshot list` не покаже всі джерела — не рестарти
kopia і жодних Deploy в Dockhand.

### Граблі (якщо колись щось упаде)

- **UI-флоу не працює**: rclone-конфіг змонтований `:ro`, тож Kopia падає з
  `unable to start rclone: timed out` (жорсткий дефолт 15 с; rclone v1.68.2
  з read-only конфігом з'їдає це вікно ретраями). Тільки CLI і
  `--rclone-startup-timeout=180s` — без нього сервер не відкриє репо
  при кожному рестарті
- **Абсолютні шляхи в UI**: відносний шлях склеюється з домашнім каталогом
  і падає з "path does not exist"
- **`Failed to save config after 10 tries`** в логах — безпечний шум від
  `:ro` маунта rclone.conf, на роботу не впливає
- rclone у цьому образі лежить у `/usr/bin/rclone` (не в PATH контейнера)
- Монітор Kopia в Uptime Kuma: приймати коди `200-299,401` — Kopia віддає
  логін-сторінку з кодом 401 (браузер її рендерить, чекер — ні)

## Доступ до сервісів (HTTPS через Caddy)

Bitwarden-клієнти та веб-сховище вимагають HTTPS, тому перед сервісами стоїть
Caddy з власним внутрішнім CA. Усі сервіси з веб-сторінкою доступні як
`https://<ім'я>.home:8443`:

`vault.home` (8192), `jellyfin.home` (8096), `qbittorrent.home` (8080),
`navidrome.home` (4533), `immich.home` (2283), `stirling.home` (3010),
`libretranslate.home` (3020), `kuma.home` (3001), `kopia.home` (51515),
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
  for h in vault jellyfin qbittorrent navidrome immich stirling libretranslate kuma kopia homepage; do
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
  sudo ufw allow from "$SUBNET" to any port 8192,8096,8080,4533,2283,3010,3020,3001,3002,51515 proto tcp
  ```

## Дашборд Homepage

`https://homepage.home:8443` — головний екран із усіма сервісами.

- Конфіг: `docker/admin/homepage/` (`settings.yaml`, `services.yaml`,
  `widgets.yaml`, `bookmarks.yaml`, `custom.css`) → копіюється на сервер у
  `HOMEPAGE_CONFIG` (`/home/trip/homepage`) і бекапиться в Kopia (джерело `/sources/homepage`)
- Секрети віджетів не в репо: заповнюються в Dockhand (Env) як `HOMEPAGE_VAR_*`
  (jellyfin key, qbittorrent login, pihole token, tailscale key+tailnet+deviceid, immich key)
- Статус контейнерів — через Uptime Kuma
- Після зміни конфігу: рестарт контейнера (`docker restart homepage`)

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
- Pi-hole працює як DNS + DHCP-фільтр на весь домашній LAN, Unbound —
  рекурсивний резолвер, щоб не ходити до чужих DNS-серверів.
- Tailscale підіймає exit node, тому весь трафік з телефону/ноута може йти
  через домашню мережу коли я не вдома.
- IP-діапазон `192.168.1.0/24` в `TS_EXTRA_ARGS` — стандартна приватна
  підмережа, не унікальна інформація, але заміни якщо у тебе інша.

