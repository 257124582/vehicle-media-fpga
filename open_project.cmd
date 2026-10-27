@echo off
setlocal
cd /d "%~dp0"
if not defined PYTHON_EXE set "PYTHON_EXE=python"
"%PYTHON_EXE%" tools\prepare_project.py
if errorlevel 1 exit /b 1
start "" "project\vehicle_media.al"
