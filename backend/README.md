# Band backend

The existing theory and chat routes remain unchanged. Band routes live under `/v1` and use async SQLAlchemy, PostgreSQL, Redis Queue, private Cloudflare R2 objects, Sign in with Apple, and APNs. Band appearance and mood-board cards reuse the private asset pipeline; board image access remains membership-authorized and short lived.

## Local verification

Create a virtual environment, install `requirements.txt`, and set at least:

```sh
export OPENAI_API_KEY=test
export DATABASE_URL=sqlite+aiosqlite:////tmp/stew-band.db
export BAND_INLINE_JOBS=true
alembic -c alembic.ini upgrade head
PYTHONPATH=. pytest -q tests
```

R2 and Apple credentials are not required for model/authorization tests. Real authentication and upload calls deliberately return a configuration error until those services are configured.

## Production order

1. Create a private R2 bucket. Keep public access disabled and create credentials limited to object read, write, and delete for that bucket.
2. Configure the Apple App ID for Sign in with Apple, Push Notifications, and Associated Domains. Create separate Sign in with Apple and APNs keys if desired.
3. Review the launch-draft Terms, Privacy, Support, and Safety pages served at
   `/legal/terms`, `/legal/privacy`, `/support`, and `/safety`. Keep the Render
   URL values in `.env.example` synchronized if the public hostname changes.
4. Create a manually managed Render environment group named `stew-band-secrets` from `.env.example`, then sync `render.yaml`. The Blueprint references this existing group but deliberately does not manage its secret values. Confirm the stable public hostname matches `PUBLIC_BASE_URL` and the iOS Associated Domains entitlement.
5. Let the web service pre-deploy command apply Alembic migrations. Do not use `BAND_AUTO_CREATE_DB` in production.
6. Verify `/health/ready`, the web and worker logs, the upload-cleanup cron, the AASA response, and APNs sandbox before switching APNs to production.

Generate `APPLE_TOKEN_ENCRYPTION_KEY` with the command documented in `.env.example`. Apple and R2 secrets belong only in Render; the iOS app receives short-lived HTTPS URLs and never receives storage credentials.

The Docker image includes `ffprobe` for audio/video codec and duration validation plus HEIC-aware image validation. Upload reservations count against the 2 GB Band limit until validation succeeds or cleanup releases them.

## Background queues

The worker consumes `media` and `notifications`. Media jobs validate uploads and delete R2 objects. Notification jobs retry transient APNs failures and disable invalid device tokens. A Render cron releases abandoned upload reservations every 15 minutes.

## Required deployment values

Use `backend/.env.example` as the authoritative variable list. The most important values are PostgreSQL/Redis URLs, `APP_JWT_SECRET`, the Fernet encryption key, Apple Team/Bundle/Key values, APNs Key values, private R2 credentials, platform-admin Apple subject IDs, and published legal/support URLs.

`DATABASE_URL` and `REDIS_URL` are supplied by the Blueprint resources and must not be copied into `stew-band-secrets`. Keep `BAND_INLINE_JOBS=false` and `BAND_AUTO_CREATE_DB=false` in production; Alembic owns production schema changes.
