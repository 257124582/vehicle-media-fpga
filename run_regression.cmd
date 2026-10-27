@echo off
setlocal
cd /d "%~dp0"
if not defined PYTHON_EXE set "PYTHON_EXE=python"
for %%S in (run_all run_mixed_media run_sdram_backend run_system run_v3_extra run_vehicle_top) do (
  "%PYTHON_EXE%" tools\%%S.py
  if errorlevel 1 exit /b 1
)
exit /b 0
