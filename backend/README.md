# Backend

The backend is a FastAPI application.

## Run locally

From the repository root:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --app-dir backend --host 127.0.0.1 --port 8000
```

The backend reads its environment file from `backend/.env` and stores local SQLite data in `backend/alkawn.db`.

## Layout

- `app/main.py`: API application, models, authentication, and routes.
- `media/`: uploaded media files for local development.
- `.env.example`: server configuration template; copy it to `.env` and fill in the values.
- `requirements.txt`: pinned Python dependencies.
