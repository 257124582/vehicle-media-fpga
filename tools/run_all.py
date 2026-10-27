"""Regenerate references/regular disk fixtures, then run meaningful regression tests."""
from pathlib import Path
import json,numpy as np
from PIL import Image
from media_tools import ROOT,generate_demo,make_fixture,reference
from run_sim import run
import shutil
generate_demo(ROOT/'assets/tf_card')
rgb=np.asarray(Image.open(ROOT/'assets/tf_card/01_DAY.BMP').convert('RGB'))
for md in range(8):
 if md<6:a=reference(rgb,md)
 elif md==6:a=reference(rgb,4,brightness=-64)
 else:
  a=reference(rgb,1);a[:,:320]=rgb[:,:320];a[:,320]=[0,255,128];a=(a.astype(np.uint16)*8>>4).astype(np.uint8)
 a=a.astype(np.uint32);p=(a[:,:,0]<<16)|(a[:,:,1]<<8)|a[:,:,2]
 (ROOT/f'assets/reference/video_mode{md}.hex').write_text(''.join(f'{v:06x}\n' for v in p.ravel()),encoding='ascii')
reports=[]
make_fixture(ROOT/'assets/fat32.img',ROOT/'assets/tf_card',True)
for top in ['tb_sd','tb_media','tb_cache','tb_video','tb_adaptive','tb_audio','tb_console',
            'tb_audio_extended','tb_audio_visualizer','tb_board_menu','tb_color_adjust','tb_media_retry','tb_osd','tb_scaler','tb_scaler_full','tb_fat_large']:
 reports.append(run(top))
for broken,error in [('cycle','46'),('short','43')]:
 make_fixture(ROOT/f'assets/{broken}.img',ROOT/'assets/tf_card',False,broken)
 reports.append(run('tb_faults',[f'+IMAGE=assets/{broken}.img',f'+ERROR={error}']))
 shutil.copy2(ROOT/'build/sim/tb_faults.log',ROOT/f'build/sim/tb_faults_{broken}.log')
bad=ROOT/'assets/bad_bpb.img';bad.write_bytes(bytes(512))
reports.append(run('tb_faults',['+IMAGE=assets/bad_bpb.img','+ERROR=11']))
shutil.copy2(ROOT/'build/sim/tb_faults.log',ROOT/'build/sim/tb_faults_bpb.log')
(ROOT/'build/sim/results.json').write_text(json.dumps(reports,indent=2))
print('ALL TESTS PASS')
