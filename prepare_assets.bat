@echo off
setlocal
set "ROOT=%~dp0"
if not exist "%ROOT%assets\images" mkdir "%ROOT%assets\images"
for %%F in ("%ROOT%school_item.png" "%ROOT%464.png" "%ROOT%87876.png" "%ROOT%3444444444.png") do if exist "%%~F" copy /Y "%%~F" "%ROOT%assets\images\" >nul
echo Images are ready in assets\images
pause