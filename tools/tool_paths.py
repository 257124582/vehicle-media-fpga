"""Locate installed synthesis and simulation tools."""
from pathlib import Path
import os,shutil
def td_executable():
    candidates=[os.environ.get('TD_EXE'),shutil.which('td_commands_prompt.exe'),'D:/TD/bin/td_commands_prompt.exe','C:/TD/bin/td_commands_prompt.exe']
    for item in candidates:
        if item and Path(item).is_file():return str(Path(item))
    raise FileNotFoundError('Set TD_EXE to td_commands_prompt.exe or add the TD bin directory to PATH.')
def simulation_directory():
    located=shutil.which('vsim.exe')
    candidates=[os.environ.get('MODELSIM_BIN'),str(Path(located).parent) if located else None,'E:/modelsim/win64pe']
    for item in candidates:
        if item and all((Path(item)/name).is_file() for name in ['vsim.exe','vlog.exe','vlib.exe']):return Path(item)
    raise FileNotFoundError('Set MODELSIM_BIN to the directory containing vsim.exe, vlog.exe and vlib.exe.')
