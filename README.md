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
| Kopia | бекап конфігів у Google Drive | 51515 |
| Caddy | HTTPS-проксі з внутрішнім CA (`https://vault.home:8443`) | 8443 |

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
pihole, tailscale, stirling, vaultwarden, uptime-kuma) у Google Drive через
Kopia + rclone. Тільки налаштування — фото, музика і торенти не входять.

Разова підготовка на сервері:

1. `rclone config --config /home/trip/kopia/rclone.conf` → remote `gdrive`
   (OAuth через браузер, client_id лишити порожнім — внутрішній ключ rclone
   для конфігів цілком тягне)
2. Перевірка: `rclone lsd --config /home/trip/kopia/rclone.conf gdrive:`
3. У веб-UI Kopia (http://host:51515): **Repository → Rclone** → remote path
   `gdrive:kopia` (папку створить сама), пароль — `KOPIA_PASSWORD` з `.env`
4. Створити снапшот-сети для потрібних `/sources/*` (jellyfin, qbittorrent,
   navidrome, pihole, dnsmasq, tailscale, stirling, vaultwarden, uptime-kuma) →
   політика «щодня 02:00, 30 денних + 12 місячних» → перший бекап вручну

## Доступ до Vaultwarden

Vaultwarden (як і всі Bitwarden-клієнти) вимагає HTTPS, тому перед ним стоїть
Caddy з власним внутрішнім CA — адреса `https://vault.home:8443`.

- **Вдома** — просто відкриваєш адресу, tailscale не потрібен. Один раз
  встанови CA-сертифікат Caddy на пристрій:
  `docker compose exec caddy cat /data/caddy/pki/authorities/local/root.crt`
  → Android: Налаштування → Безпека → Встановити сертифікат → CA
- **Поза домом** — увімкни tailscale на телефоні. У Tailscale admin console
  (DNS → Nameservers → Custom → tailnet IP сервера + Override local DNS)
  налаштований pihole як DNS, тож `vault.home` резолвиться і трафік іде через
  маршрут `192.168.1.0/24`
- У Pi-hole має бути Local DNS record: `vault.home` → LAN IP сервера
- Запис `VAULTWARDEN_DOMAIN` у `.env` має збігатися з адресою вище

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

