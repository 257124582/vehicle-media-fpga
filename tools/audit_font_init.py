"""Compare every generated glyph word with mapped BRAM INIT data."""
from pathlib import Path
import re,json,hashlib,sys
ROOT=Path(__file__).resolve().parents[1]
netlist=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'build/td/vehicle_media_gate.v'
s=netlist.read_text(encoding='utf-8')
rtl=(ROOT/'rtl/vehicle_font.v').read_text(encoding='utf-8')
expected=[0]*3200
for a,v in re.findall(r"rom\[(\d+)\]=16'h([0-9a-fA-F]+)",rtl):expected[int(a)]=int(v,16)
actual=[0]*3200
slices=[]
for block in s.split('EG_PHY_BRAM #(')[1:]:
    block=block.split('));',1)[0]
    if 'u_vehicle_osd/font/ramread' not in block:continue
    m=re.search(r'font_bits \[(\d+):(\d+)\]',block);hi,lo=map(int,m.groups())
    assert hi-lo==1 and '.DATA_WIDTH_A("2")' in block and '.WEAMUX("0")' in block
    init={int(i,16):int(v,16) for i,v in re.findall(r"\.INIT_([0-9A-F]{2})\(256'h([0-9A-Fa-f]+)\)",block)}
    assert len(init)==32
    for a in range(3200):actual[a]|=((init[a//128]>>(2*(a%128)))&3)<<lo
    slices.append(lo)
assert sorted(slices)==list(range(0,16,2)),slices
assert actual==expected,[(i,a,b) for i,(a,b) in enumerate(zip(actual,expected)) if a!=b][:10]
r={'passed':True,'words_compared':3200,'bits_per_word':16,'bram_slices':8,'netlist_sha256':hashlib.sha256(s.encode('utf-8')).hexdigest(),'font_sha256':hashlib.sha256((ROOT/'rtl/vehicle_font.v').read_bytes()).hexdigest(),'method':'Reconstruct all font words from eight mapped EG_PHY_BRAM INIT parameter banks and compare to RTL constants.'}
(netlist.parent/'font_init_audit.json').write_text(json.dumps(r,indent=2),encoding='utf-8')
print(json.dumps(r))
