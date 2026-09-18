$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildScript = Join-Path $root 'build_apk.bat'
$flutter = 'D:\src\flutter\bin\flutter.bat'
$watchPaths = @('lib', 'assets', 'android', 'pubspec.yaml', 'pubspec.lock')
$watchers = @()
$pending = $false
$lastChange = [DateTime]::MinValue
$webServerProcess = $null

function Start-WebPreview {
    if (-not $webServerProcess -or $webServerProcess.HasExited) {
        $python = 'C:\Users\angin\AppData\Local\Python\bin\python.exe'
        if (-not (Test-Path $python)) {
            $python = (Get-Command python -ErrorAction SilentlyContinue).Source
        }
        if (-not $python) {
            Write-Host 'Python was not found; browser preview was not started.' -ForegroundColor Red
            return
        }
        $webServerProcess = Start-Process -FilePath $python -PassThru -WorkingDirectory $root -ArgumentList @(
            '-m', 'http.server', '8080', '--directory', (Join-Path $root 'build\web')
        )
    }

    Start-Process -FilePath 'http://localhost:8080'
}

function Start-ApkBuild {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Building APK..." -ForegroundColor Cyan
    & $buildScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] APK updated." -ForegroundColor Green
    } else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] APK build failed; old APK was preserved." -ForegroundColor Red
    }
}

function Update-WebPreview {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Updating browser preview..." -ForegroundColor Cyan
    & $flutter build web | Out-Host
    Start-WebPreview
}

foreach ($relativePath in $watchPaths) {
    $fullPath = Join-Path $root $relativePath
    $watcher = New-Object IO.FileSystemWatcher
    $watcher.Path = if (Test-Path $fullPath -PathType Container) { $fullPath } else { Split-Path $fullPath }
    $watcher.Filter = if (Test-Path $fullPath -PathType Container) { '*.*' } else { Split-Path $fullPath -Leaf }
    $watcher.IncludeSubdirectories = Test-Path $fullPath -PathType Container
    $watcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size, DirectoryName'
    $watcher.EnableRaisingEvents = $true
    Register-ObjectEvent $watcher Changed -Action { $script:pending = $true; $script:lastChange = Get-Date } | Out-Null
    Register-ObjectEvent $watcher Created -Action { $script:pending = $true; $script:lastChange = Get-Date } | Out-Null
    Register-ObjectEvent $watcher Deleted -Action { $script:pending = $true; $script:lastChange = Get-Date } | Out-Null
    Register-ObjectEvent $watcher Renamed -Action { $script:pending = $true; $script:lastChange = Get-Date } | Out-Null
    $watchers += $watcher
}

Write-Host 'APK watcher is running. Press Ctrl+C to stop.' -ForegroundColor Yellow
Start-WebPreview
Update-WebPreview
Start-ApkBuild
while ($true) {
    Start-Sleep -Milliseconds 500
    if ($pending -and ((Get-Date) - $lastChange).TotalSeconds -ge 2) {
        $pending = $false
        Update-WebPreview
        Start-ApkBuild
    }
}
