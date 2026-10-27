"""Run installed TD normally in an ASCII staging directory and preserve build evidence."""
from pathlib import Path
import shutil,tempfile,subprocess,json,time,sys,re,hashlib
from prepare_project import prepare,ROOT
from tool_paths import td_executable
def build():
    files=prepare();stage=Path(tempfile.mkdtemp(prefix='hx4s20_td_'));out=ROOT/'build/td';out.mkdir(parents=True,exist_ok=True)
    for folder in ['rtl','vendor','constraints','project','user_source']:shutil.copytree(ROOT/folder,stage/folder)
    al=stage/'project/vehicle_media.al';al.write_text(al.read_text(encoding='utf-8').replace((ROOT/'project').as_posix(),(stage/'project').as_posix()),encoding='utf-8')
    # Direct CLI analysis avoids GUI project dependencies; the .al remains available for GUI use.
    script=['cd project','import_device eagle_s20.db -package EG4S20BG256']
    for p in files:
        if p.endswith('global_def.v'):continue
        script.append('analyze -file {../'+p+'} -global_include {../vendor/include/global_def.v} -include_dir {../vendor/include}')
    script+=['elaborate -top vehicle_media_top','read_adc ../constraints/pin.adc','read_sdc ../constraints/timing.sdc',
     'optimize_rtl','report_area -file vehicle_media_rtl.area','export_db vehicle_media_rtl.db',
     'set_param gate eram_init on','optimize_gate -maparea vehicle_media_gate.area -mapsim vehicle_media_gate.v','legalize_phy_inst','update_timing',
     'report_timing_summary -file vehicle_media_gate.timing','export_db vehicle_media_gate.db',
     'place','update_timing -mode manhattan','report_timing_summary -file vehicle_media_place.timing',
     'route','fix_hold','update_timing -mode final','report_area -io_info -file vehicle_media_phy.area',
     'report_timing_status -file vehicle_media_phy.ts','report_timing_summary -file vehicle_media_pr.timing',
     'report_timing_exception -file vehicle_media_exceptions.timing','report_clock_utilization -file clocks.txt',
     'export_db vehicle_media_pr.db','bitgen -bit vehicle_media.bit','puts {BUILD COMPLETE}','exit']
    (stage/'build.tcl').write_text('\n'.join(script)+'\n',encoding='ascii');shutil.copy2(stage/'build.tcl',out/'build.tcl')
    (out/'stage.json').write_text(json.dumps({'path':str(stage)},indent=2))
    print('TD staging '+str(stage),flush=True);t0=time.time()
    with (out/'console.log').open('wb') as log:
        p=subprocess.run([td_executable(),'build.tcl'],cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=3600)
    for f in list(stage.iterdir())+list((stage/'project').iterdir()):
        if f.is_file() and f.suffix in ['.area','.timing','.ts','.txt','.bit','.log','.logw','.v']:
            shutil.copy2(f,out/f.name)
    generated=(stage/'project/vehicle_media.bit').exists() and b'BUILD COMPLETE' in (out/'console.log').read_bytes()
    timing=(stage/'project/vehicle_media_phy.ts').read_text() if (stage/'project/vehicle_media_phy.ts').exists() else ''
    sw=re.search(r'SWNS:\s*([-\d.]+)',timing);hw=re.search(r'HWNS:\s*([-\d.]+)',timing)
    timing_passed=bool(sw and hw and float(sw[1])>=0 and float(hw[1])>=0)
    good=generated and timing_passed
    source_hashes={f:hashlib.sha256((stage/f).read_bytes()).hexdigest() for f in files+['constraints/pin.adc','constraints/timing.sdc']}
    report={'gate_eram_init':'on','exit':p.returncode,'bit_generated':generated,'timing_passed':timing_passed,'setup_wns_ns':float(sw[1]) if sw else None,
     'hold_wns_ns':float(hw[1]) if hw else None,'seconds':round(time.time()-t0,2),'stage':str(stage),'source_sha256':source_hashes}
    (out/'result.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k!='source_sha256'}))
    # Retain this known temp directory for diagnosing/restarting place and route.
    if not good:
        sys.stdout.reconfigure(encoding='utf-8');print((out/'console.log').read_bytes().decode('utf-8',errors='replace')[-5000:]);sys.exit(1)
if __name__=='__main__':build()
