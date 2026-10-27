from pathlib import Path
from run_sim import run,ROOT
sources=[p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl').glob('*.v') if p.name not in ['media_sys_pll.v','media_video_pll.v','sd_spi_reader.v']]+['sim/system_models.v']
run('tb_vehicle_top',sources=sources,defines=['SIM_MEMORY_MODEL'])
