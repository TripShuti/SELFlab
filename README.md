# SELFlab

Конфіги та docker-compose стеки мого домашнього сервера. Тут те, що реально
крутиться 24/7 — медіа, бекапи фото, мережа, дрібні self-hosted утиліти.

## Стек

| Сервіс | Що робить | Порт |
|---|---|---|
| Jellyfin | медіасервер | 8096 |
| qBittorrent | торент-клієнт | 8080 |
| Navidrome | музичний стрімінг (Subsonic API) | 4533 |
| Immich | бекап і галерея фото з телефону | 2283 |
| Pi-hole + Unbound | DNS-фільтрація реклами, свій рекурсивний резолвер | 80/443 |
| Tailscale | VPN / exit node для доступу ззовні | — |
| Stirling PDF | робота з PDF (мердж, OCR, конвертація) | 3010 |
| LibreTranslate | self-hosted переклад тексту | 3020 |

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

Кожна папка в `docker/` — окремий стек із власним `docker-compose.yml`.
Там, де є секрети, лежить `.env.example` — копіюй у `.env` і заповнюй
своїми значеннями, сам `.env` в git не потрапляє (див. `.gitignore`).

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

1. **Git Integration** → зробити форк, прописати всі свої шляхи, та додати свій репозиторій у Dockhand
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

- Шляхи типу `/home/trip/...` і `/mnt/ssd/...` — специфічні для мого сервера,
  під свою машину заміни на власні.
- Pi-hole працює як DNS + DHCP-фільтр на весь домашній LAN, Unbound —
  рекурсивний резолвер, щоб не ходити до чужих DNS-серверів.
- Tailscale підіймає exit node, тому весь трафік з телефону/ноута може йти
  через домашню мережу коли я не вдома.
- IP-діапазон `192.168.1.0/24` в `TS_EXTRA_ARGS` — стандартна приватна
  підмережа, не унікальна інформація, але заміни якщо у тебе інша.

