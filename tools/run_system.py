from pathlib import Path
from run_sim import run,ROOT
sources=[p.relative_to(ROOT) for p in sorted((ROOT/'rtl').glob('*.v')) if p.name not in
         ['media_sys_pll.v','media_video_pll.v','sd_spi_reader.v','media_osd.v','audio_visualizer.v']]
sources.append(Path('sim/system_models.v'))
sources.append(Path('sim/raw_display_models.v'))
run('tb_system',sources=sources,defines=['SIM_MEMORY_MODEL','SIM_RAW_DISPLAY'])
