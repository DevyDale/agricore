# Real-time chat & Redis

Agricore's chat and presence run on Django **Channels** websockets
(`ws/chat/<conversation_id>/`). The channel layer is what fans websocket
messages out to the right connections.

## How the channel layer is chosen

`settings.py` picks the backend from the `REDIS_URL` env var:

| `REDIS_URL` | Backend | Use for |
|-------------|---------|---------|
| empty / unset | `InMemoryChannelLayer` | local dev, single-process demos |
| set | `RedisChannelLayer` (`channels_redis`) | production / any multi-worker deploy |

In-memory state lives inside **one process**, so it's perfect for `runserver`
and Phase-0 demos but **cannot** be used in production — with several workers,
a message sent on worker A wouldn't reach a socket on worker B.

## Local development

Nothing to install or run — leave `REDIS_URL` empty in `.env` and chat works
in-memory under `runserver`:

```bash
cd agricore_project
myenv/bin/python manage.py runserver   # serves HTTP + websockets via daphne
```

(`daphne` must be installed and first in `INSTALLED_APPS` — already wired — so
`runserver` serves the ASGI app. Without it, `ws/...` routes 404.)

If you'd rather mirror production locally, run a Redis and point at it:

```bash
brew services start redis
# in .env:
REDIS_URL=redis://localhost:6379/0
```

## Production (required)

Multi-worker production **must** set `REDIS_URL` to a reachable managed Redis.
Any provider works; managed options need no server admin:

1. Create a Redis instance (e.g. Upstash free tier, Redis Cloud, or your host's
   add-on). TLS endpoints use the `rediss://` scheme.
2. Set it in the production environment:
   ```ini
   REDIS_URL=rediss://default:<password>@<host>:<port>
   ```
3. Run the app under an ASGI server that uses `agricore_project.asgi:application`
   (daphne or uvicorn), e.g.:
   ```bash
   daphne -b 0.0.0.0 -p 8000 agricore_project.asgi:application
   ```
4. Confirm websockets connect (an authed participant gets `101 Switching
   Protocols`; non-participants get `403`).

> The earlier Upstash instance (`comic-piranha-46027.upstash.io`) is gone —
> DNS now returns NXDOMAIN. Provision a fresh one before going live; until then
> chat would 500 on connect in any deploy that sets that dead URL.
