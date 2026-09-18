@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "PYTHON=%ROOT%\.venv\Scripts\python.exe"

if not exist "%PYTHON%" (
    where python >nul 2>&1
    if errorlevel 1 (
        echo Python was not found. Create the virtual environment first.
        pause
        exit /b 1
    )
    set "PYTHON=python"
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$test = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue; if ($test) { exit 0 } else { exit 1 }"
if errorlevel 1 (
    echo Starting the authentication server...
    start "Alkawn API" /D "%ROOT%" cmd /k ""%PYTHON%" -m uvicorn app.main:app --app-dir backend --host 127.0.0.1 --port 8000"
)

echo Waiting for the authentication server...
set "READY="
for /L %%I in (1,1,20) do (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $null = Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8000/health -TimeoutSec 1; exit 0 } catch { exit 1 }"
    if not errorlevel 1 (
        set "READY=1"
        goto :server_ready
    )
    timeout /t 1 /nobreak >nul
)

if not defined READY (
    echo The authentication server did not start on port 8000.
    pause
    exit /b 1
)

:server_ready
echo Authentication server is ready.
where flutter >nul 2>&1
if errorlevel 1 (
    echo Flutter was not found in PATH.
    pause
    exit /b 1
)

cd /d "%ROOT%"
flutter run -d chrome
endlocal
