@echo off
REM Double-click to compile NoteCraft AI APK using a new private GitHub repository.
REM This requires Git for Windows, GitHub CLI, GitHub login and an internet connection.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD_APK_ON_GITHUB.ps1"
if errorlevel 1 (
    echo.
    echo Build failed. Read the error above and check GitHub Actions logs.
) else (
    echo.
    echo Look for NoteCraft_AI.apk in this folder.
)
pause
