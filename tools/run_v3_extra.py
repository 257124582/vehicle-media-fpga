import json
from run_sim import run,ROOT
from pathlib import Path
reports=[]
for top in ['tb_vehicle_scene','tb_vehicle_keys','tb_vehicle_osd']:
    reports.append(run(top))
(ROOT/'build/sim/v3_extra_results.json').write_text(json.dumps(reports,indent=2))
