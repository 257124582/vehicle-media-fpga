"""Exercise the supplied encrypted controller with APUG011's SDRAM bus model."""
from pathlib import Path
import subprocess,tempfile,shutil,time,json
ROOT=Path(__file__).resolve().parents[1]
from tool_paths import simulation_directory
SIM=simulation_directory()
def run():
    stage=Path(tempfile.mkdtemp(prefix='hx4s20_sip_sim_')).resolve()
    logs=[];t0=time.time();out=ROOT/'build/sim';out.mkdir(parents=True,exist_ok=True)
    try:
        for folder in ['rtl','vendor','user_source','tests','sim']:
            shutil.copytree(ROOT/folder,stage/folder)
        (stage/'user_source/hdl_source/include/global_def.v').write_bytes((stage/'vendor/include/global_def.v').read_bytes())
        workdir=stage/'project';workdir.mkdir()
        def command(args):
            p=subprocess.run([str(x) for x in args],cwd=workdir,capture_output=True,timeout=600)
            s=(p.stdout+p.stderr).decode('utf-8',errors='replace');logs.append(s)
            if p.returncode:raise RuntimeError(s[-5000:])
            return s
        command([SIM/'vlib.exe','work'])
        command([SIM/'vlog.exe','+incdir+'+str(stage/'vendor/include'),stage/'vendor/include/global_def.v',
          stage/'vendor/include/sdr_init_ref.enc.v',stage/'vendor/include/sdr_wrrd.enc.v',
          stage/'vendor/include/sdr_as_ram.enc.v',stage/'vendor/simulation/IS42s32200.v',
          stage/'sim/sdram_sip_model.v',stage/'rtl/frame_cache.v'])
        command([SIM/'vlog.exe','-sv',stage/'tests/tb_sdram_backend.sv'])
        s=command([SIM/'vsim.exe','-c','-voptargs=+acc','tb_sdram_backend','-do',
          'onbreak {quit -code 2}; onerror {quit -code 3}; run -all; quit -code 0'])
        assert 'TEST PASS SDRAM_BACKEND' in s,s[-5000:]
        assert 'ERROR:' not in s,'SDRAM bus model reported a timing violation\n'+s[-5000:]
        print(json.dumps({'passed':True,'seconds':round(time.time()-t0,2)}))
    finally:
        (out/'tb_sdram_backend.log').write_text('\n'.join(logs),encoding='utf-8')
        assert stage.name.startswith('hx4s20_sip_sim_') and stage.parent==Path(tempfile.gettempdir()).resolve()
        shutil.rmtree(stage)
if __name__=='__main__':run()
