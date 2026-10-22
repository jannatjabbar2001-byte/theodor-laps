@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "FLUTTER=flutter"

if not defined API_BASE_URL (
    echo API_BASE_URL is required for a production Web build.
    exit /b 1
)

echo %API_BASE_URL% | findstr /b /c:"https://" >nul
if errorlevel 1 (
    echo API_BASE_URL must use HTTPS for a production Web build.
    exit /b 1
)

if not defined BASE_HREF set "BASE_HREF=/"

pushd "%ROOT%"
call "%FLUTTER%" pub get
if errorlevel 1 goto :failed
call "%FLUTTER%" build web --release --base-href="%BASE_HREF%" --dart-define=API_BASE_URL=%API_BASE_URL%
if errorlevel 1 goto :failed
popd
echo Web release created at:
echo %ROOT%\build\web
exit /b 0

:failed
popd
echo Web release build failed.
exit /b 1