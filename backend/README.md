# Backend

The backend is a FastAPI application. It reads `backend/.env`; keep that file and
all service credentials out of source control and the Flutter application.

## Local development

From the repository root:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --app-dir backend --host 127.0.0.1 --port 8000
```

When `DATABASE_URL` is unset, development falls back to `backend/alkawn.db`.
SQLite table creation and development-only seed accounts are restricted to that
local database. PostgreSQL schema changes must be applied with migrations; the
application does not create PostgreSQL tables at startup.

## Supabase PostgreSQL and Cloudflare R2

For a cloud-backed deployment, set `DATABASE_URL` to the intended Supabase
PostgreSQL connection string and set `ENVIRONMENT=production`. Production
startup rejects SQLite and requires the server-side Supabase and R2 settings
listed in `.env.example`. `FRONTEND_ORIGIN` must be the HTTPS origin of the
deployed Flutter web app (without a path).

Before changing the Supabase schema, take and verify a database backup. Then
review and apply `migrations/20261023_community_cloud.sql` to that same project.
It creates the community tables additively, does not import SQLite community
records, and schedules public-message expiry with Supabase `pg_cron`. Private
messages have no expiry. The backend also runs a periodic cleanup while it is
online.

Community avatars are stored in R2 and their object keys in
`community_profiles.avatar_filename`. Videos continue to use the existing R2
presigned-upload flow; their object keys remain in PostgreSQL. R2 credentials
must only be configured on the backend.

## Layout

- `app/main.py`: API application, models, authentication, and routes.
- `media/`: local-development-only avatar storage.
- `migrations/`: additive PostgreSQL migrations; back up before applying.
- `.env.example`: server configuration template; copy it to `.env` and fill in
  values without committing the file.
- `requirements.txt`: pinned Python dependencies.
