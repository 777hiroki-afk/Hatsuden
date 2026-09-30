@echo off
rem Start solar_logger.py and smart_notifier.py in the background (pythonw).
rem Uses this .bat's own folder, so no hard-coded (Japanese) path is needed.
setlocal
cd /d "%~dp0"

call :launch SolarLogger solar_logger.py
call :launch SmartNotifier smart_notifier.py
exit /b 0

rem ---- :launch <title> <script> : start only if not already running ----
:launch
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'pythonw.exe' -and $_.CommandLine -like '*%~2*' }) { exit 1 } else { exit 0 }"
if errorlevel 1 (
    echo %~2 is already running. skip.
    exit /b 0
)
start "%~1" pythonw "%~2"
exit /b 0
