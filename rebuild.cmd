@echo off
setlocal
cd /d "%~dp0"
if not defined PYTHON_EXE set "PYTHON_EXE=python"
"%PYTHON_EXE%" tools\build_td.py
if errorlevel 1 exit /b 1
"%PYTHON_EXE%" tools\audit_font_init.py
exit /b %errorlevel%
