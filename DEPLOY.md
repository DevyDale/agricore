# Deploying Agricore to Render

The repo is Render-ready via [`render.yaml`](render.yaml) (a Blueprint). It defines
a **web service** (Django served by **daphne**, so chat/notifications websockets
work) and a **Redis** Key-Value store (the Channels layer).

Payments stay in **sandbox** (`PESAPAL_ENV=sandbox`) — real-money checkout needs a
KYC'd merchant account, which is a later step. Everything else runs for real.

## 1. Deploy branch — use `dev`, NOT `main`
⚠️ `main` is an **old, separate backend-only history** (unrelated to `dev`, and
missing whole apps: payments, escrow, notifications, templates, …). Do **not**
deploy it. The current, complete app is on **`dev`**, and `render.yaml` already
pins `branch: dev`. Nothing to merge — just make sure `dev` is pushed:

```bash
git push origin dev
```
(One day you may want to reset `main` to match `dev` for convention, but that's a
destructive history change — skip it for now; deploying from `dev` is correct.)

## 2. Create the Blueprint on Render
1. Render Dashboard → **New +** → **Blueprint** → connect the GitHub repo.
2. Render reads `render.yaml` and creates **agricore** (web) + **agricore-redis**.
   `SECRET_KEY` is auto-generated; `REDIS_URL` is auto-wired.

## 3. Set the secret env vars (web service → Environment)
These are `sync: false` (never in git) — set them in the dashboard:

| Var | Value |
|-----|-------|
| `ALLOWED_HOSTS` | `agricore.onrender.com` (+ any custom domain) |
| `DATABASE_URL` | your Supabase Postgres connection string |
| `CEREBRAS_API_KEY` | Dale AI key |
| `GEMINI_API_KEY` | crop diagnosis (optional) |
| `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_IDS` | Google login |
| `PESAPAL_CONSUMER_KEY` / `PESAPAL_CONSUMER_SECRET` | Pesapal **sandbox** keys |
| `SMS_PROVIDER` / `AT_USERNAME` / `AT_API_KEY` | Africa's Talking SMS |

> `RENDER_EXTERNAL_HOSTNAME` is auto-trusted by `settings.py` (added to
> `ALLOWED_HOSTS` + `CSRF_TRUSTED_ORIGINS`), so the `.onrender.com` host works even
> before you set `ALLOWED_HOSTS`.

## 4. Deploy
The build runs `pip install` → `collectstatic` → `migrate`, then starts daphne.
- **First deploy:** if the initial build runs before `DATABASE_URL` is set, the
  `migrate` step fails — just set the env vars (step 3) and **Manual Deploy →
  Deploy latest commit**.

## 5. Post-deploy
- Create an admin: web service → **Shell** → `python manage.py createsuperuser`.
- If using Google login, add `https://agricore.onrender.com` to the OAuth client's
  authorized origins/redirect URIs.
- Verify: open `https://agricore.onrender.com/auth/`, sign in, send a chat message
  (confirms websockets + Redis), and ask Dale something (confirms the LLM key).

## Notes / gotchas
- **Free tier sleeps** after inactivity (first request is slow) and Redis is small
  (fine for chat presence/pubsub). Upgrade instance types for real traffic.
- **Static files** use WhiteNoise + manifest hashing (validated locally).
- **Realtime requires Redis** across workers — it's provisioned by the Blueprint;
  don't unset `REDIS_URL`.
- **Production payments later:** set `PESAPAL_ENV=live` + live keys, register the
  live IPN against `https://<domain>/payments/ipn/`, once a merchant account exists.

## Making edits over time (continuous deploy)
Render auto-deploys on every push to the connected branch (`dev`). So the loop is:

```bash
# make changes...
git add -A && git commit -m "…" && git push origin dev
```

Each push triggers a build (`pip install` → `collectstatic` → `migrate`) and a
zero-downtime swap. New DB migrations apply automatically on deploy.

Tips:
- Watch the build in the Render dashboard; a failed migrate/build won't swap in.
- For risky changes, test locally first (`runserver`) — the live site only updates
  on a successful build.
- Env-var/secret changes are made in the Render dashboard (not in git).
