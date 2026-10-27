"""Runs the installed simulator in an ASCII temp path; copies evidence back to build/."""
from pathlib import Path
import argparse, subprocess, shutil, tempfile, json, time, os
ROOT=Path(__file__).resolve().parents[1]
from tool_paths import simulation_directory
SIM=simulation_directory()
def run(top, plusargs=(), sources=None, runtime='run -all',defines=()):
    stage=Path(tempfile.mkdtemp(prefix='hx4s20_sim_'))
    out=ROOT/'build'/'sim';out.mkdir(parents=True,exist_ok=True)
    logs=[];t0=time.time()
    try:
        for folder in ['rtl','tests','assets','sim']:
            shutil.copytree(ROOT/folder,stage/folder)
        def command(args):
            result=subprocess.run([str(x) for x in args],cwd=stage,capture_output=True,timeout=2400 if top=='tb_system' else 600)
            text=(result.stdout+result.stderr).decode('utf-8',errors='replace');logs.append(text)
            if result.returncode:raise RuntimeError(text[-5000:])
            return text
        command([SIM/'vlib.exe','work'])
        paths=sources or sorted((stage/'rtl').glob('*.v'))
        if sources:paths=[stage/p for p in sources]
        command([SIM/'vlog.exe',*['+define+'+d for d in defines],*paths])
        command([SIM/'vlog.exe','-sv',stage/'tests'/f'{top}.sv'])
        sim_args=[] if top=='tb_system' else ['-voptargs=+acc']
        result=command([SIM/'vsim.exe','-c',*sim_args,top,*plusargs,'-do',f'onbreak {{quit -code 2}}; onerror {{quit -code 3}}; {runtime}; quit -code 0'])
        if 'TEST PASS' not in result:raise RuntimeError('No TEST PASS marker\n'+result[-5000:])
        for f in stage.glob('*.out'):shutil.copy2(f,out/f.name)
        report={'top':top,'passed':True,'seconds':round(time.time()-t0,2),'plusargs':list(plusargs),'simulator':'ModelSim DE-64 10.6c'}
        print(json.dumps(report));return report
    finally:
        (out/(top+'.log')).write_text('\n'.join(logs),encoding='utf-8')
        # stage was created by tempfile; no user directory is removed.
        assert stage.resolve().parent==Path(tempfile.gettempdir()).resolve() and stage.name.startswith('hx4s20_sim_')
        shutil.rmtree(stage)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('top');p.add_argument('plusargs',nargs='*');a=p.parse_args();run(a.top,a.plusargs)
