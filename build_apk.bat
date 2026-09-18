@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "FLUTTER=D:\src\flutter\bin\flutter.bat"
set "BUILD_ROOT=Z:"

if not exist "%FLUTTER%" (
	where flutter >nul 2>&1
	if errorlevel 1 (
		echo Flutter was not found. Set FLUTTER to your Flutter SDK path.
		exit /b 1
	)
	set "FLUTTER=flutter"
)

if not exist "%ROOT%\APK_OUTPUT" mkdir "%ROOT%\APK_OUTPUT"
subst Z: /d >nul 2>&1
subst Z: "%ROOT%"
if errorlevel 1 (
	echo Could not create a temporary drive for the Arabic project path.
	exit /b 1
)
pushd "%BUILD_ROOT%\"
if not exist "%ROOT%\assets\images" mkdir "%ROOT%\assets\images"
for %%F in ("%ROOT%\school_item.png" "%ROOT%\464.png" "%ROOT%\87876.png" "%ROOT%\3444444444.png") do if exist "%%~F" copy /Y "%%~F" "%ROOT%\assets\images\" >nul
call "%FLUTTER%" pub get
if errorlevel 1 goto :failed
if not defined API_BASE_URL (
	echo API_BASE_URL is required for release APK builds.
	goto :failed
)
call "%FLUTTER%" build apk --release --no-pub --dart-define=API_BASE_URL=%API_BASE_URL%
if not exist "%BUILD_ROOT%\android\app\build\outputs\apk\release\app-release.apk" goto :failed
if not exist "%BUILD_ROOT%\APK_OUTPUT\Theodore_Labs" mkdir "%BUILD_ROOT%\APK_OUTPUT\Theodore_Labs"
copy /Y "%BUILD_ROOT%\android\app\build\outputs\apk\release\app-release.apk" "%ROOT%\APK_OUTPUT\Theodore_Labs\00_Theodore_Labs.apk" >nul
if errorlevel 1 goto :failed
popd
subst Z: /d >nul 2>&1
echo APK created successfully:
echo %ROOT%\APK_OUTPUT\Theodore_Labs\00_Theodore_Labs.apk
exit /b 0

:failed
popd
subst Z: /d >nul 2>&1
echo APK build failed. No old APK was replaced.
exit /b 1