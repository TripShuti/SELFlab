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

Всі порти, шляхи і основні налаштування задаються через env — порт у таблиці
просто дефолт, його можна змінити в `.env`.

## Структура

```
homelab/
├── docker/
│   ├── media/          # jellyfin, qbittorrent, navidrome
│   ├── immich/          # фото-бекап
│   ├── network/         # pihole, tailscale
│   └── translate/       # stirling-pdf, libretranslate
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

1. **Git Integration** → зробити форк, оновити значення у відповідних
   `.env.example` (шляхи, порти, `TS_EXTRA_ARGS`, PUID/PGID), та додати свій
   репозиторій у Dockhand
2. Створити окремий **git-стек на кожну підпапку** — кожен стек вказує на свій `compose path`:
   - `docker/media`
   - `docker/immich`
   - `docker/network`
   - `docker/translate`

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

