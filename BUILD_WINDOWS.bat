@echo off
REM NoteCraft AI: build the real Android APK using Flutter + Android SDK.
REM Requirements: Flutter stable and Android Studio's SDK must be installed.
cd /d "%~dp0"
call flutter doctor
if errorlevel 1 goto fail
call flutter create . --platforms=android --project-name=notecraft_ai --org=com.notecraft
if errorlevel 1 goto fail
python scripts\patch_android.py
if errorlevel 1 goto fail
call flutter pub get
if errorlevel 1 goto fail
call flutter build apk --debug
if errorlevel 1 goto fail
echo.
echo APK: build\app\outputs\flutter-apk\app-debug.apk
pause
exit /b 0
:fail
echo.
echo Build failed. Check the messages above and README.md.
pause
exit /b 1
