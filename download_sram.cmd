@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\download_sram.ps1
exit /b %errorlevel%
