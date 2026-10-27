"""Local-only media preparation and bit-exact reference images. Never writes a device."""
from pathlib import Path
import argparse, json, struct, hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
W, H = 640, 480

def bmp_bytes(rgb, top_down=False, extra_header=0):
    rgb = np.asarray(rgb, dtype=np.uint8)
    h, w, _ = rgb.shape
    stride = (w * 3 + 3) & ~3
    rows = rgb if top_down else rgb[::-1]
    body = b''.join(row[:, ::-1].tobytes() + bytes(stride-w*3) for row in rows)
    offset = 54 + extra_header
    header = struct.pack('<2sIHHI', b'BM', offset+len(body), 0, 0, offset)
    dib = struct.pack('<IiiHHIIiiII', 40, w, -h if top_down else h, 1, 24, 0, len(body), 2835, 2835, 0, 0)
    return header+dib+bytes(extra_header)+body

def gray(rgb):
    a = np.asarray(rgb, dtype=np.int32)
    return (77*a[..., 0]+150*a[..., 1]+29*a[..., 2]+128) >> 8

def reference(rgb, mode, threshold=128, brightness=32, contrast=384):
    a = np.asarray(rgb, dtype=np.int32)
    y = gray(a)
    if mode == 0: out = a
    elif mode == 1: out = np.repeat(y[..., None], 3, -1)
    elif mode == 2: out = np.repeat(((y >= threshold)*255)[..., None], 3, -1)
    elif mode == 3:
        tl, tc, tr = y[:-2,:-2], y[:-2,1:-1], y[:-2,2:]
        ml, mr = y[1:-1,:-2], y[1:-1,2:]
        bl, bc, br = y[2:,:-2], y[2:,1:-1], y[2:,2:]
        mag = np.abs(tr+2*mr+br-tl-2*ml-bl)+np.abs(bl+2*bc+br-tl-2*tc-tr)
        edge = np.zeros_like(y)
        edge[1:-1,1:-1] = np.minimum(mag >> 2, 255)
        out = np.repeat(edge[..., None], 3, -1)
    elif mode == 4: out = np.clip(a+brightness, 0, 255)
    elif mode == 5: out = np.clip(((a-128)*contrast >> 8)+128, 0, 255)
    else: raise ValueError('mode must be 0..5')
    return out.astype(np.uint8)

def validate_bmp(path):
    data = Path(path).read_bytes()
    if len(data)<54: raise ValueError('truncated BMP')
    magic, size, _, _, offset = struct.unpack_from('<2sIHHI', data)
    dib, width, height, planes, bits, compression = struct.unpack_from('<IiiHHI', data, 14)
    stride=(width*3+3)&~3
    if not (magic == b'BM' and 40<=dib<=4096 and 1<=width<=1024 and 1<=abs(height)<=768 and
            planes==1 and bits==24 and compression==0 and 14+dib<=offset<=4096 and
            offset+stride*abs(height)<=size<=len(data)<=4194304):
        raise ValueError('expected 1..1024 x 1..768 24-bit BI_RGB, valid offset/stride/length, file <=4 MiB')
    return {'file':str(path),'bytes':len(data),'width':width,'height':abs(height),'stride':stride,
            'top_down':height<0,'offset':offset,'sha256':hashlib.sha256(data).hexdigest()}

def generate_demo(out):
    out.mkdir(parents=True, exist_ok=True)
    refdir=out.parent/'reference';refdir.mkdir(parents=True,exist_ok=True)
    try: font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 26)
    except OSError: font=ImageFont.load_default()
    colors=[((100,180,235),(90,145,70)),((7,13,35),(12,22,20)),((90,120,145),(95,110,60)),((165,205,225),(90,120,100))]
    names=['01_DAY','02_NIGHT','03_WARN','04_PARK']
    manifest=[]
    for n, (sky, ground) in enumerate(colors):
        im=Image.new('RGB',(W,H),sky); d=ImageDraw.Draw(im)
        d.rectangle((0,220,639,479),fill=ground)
        d.polygon([(260,220),(380,220),(580,479),(60,479)],fill=(45,48,52))
        for y in range(250,460,55): d.polygon([(316,y),(324,y),(330,y+28),(310,y+28)],fill=(235,225,165))
        d.line((260,220,60,479),fill=(240,240,235),width=4);d.line((380,220,580,479),fill=(240,240,235),width=4)
        if n==0:d.ellipse((480,40,545,105),fill=(255,235,115))
        if n==1:
            d.ellipse((490,40,535,85),fill=(235,240,255));d.polygon([(150,479),(290,260),(320,479)],fill=(95,95,70))
        if n==2:
            d.polygon([(95,100),(45,195),(145,195)],fill=(240,210,40),outline=(190,35,35));d.text((88,130),'!',fill=(30,30,30),font=font)
            d.rectangle((255,290,385,365),fill=(190,40,45));d.rectangle((275,270,365,300),fill=(140,195,230))
        if n==3:
            d.rectangle((440,95,520,175),fill=(25,75,175));d.text((470,108),'P',fill='white',font=font)
            for x in (90,155,485,550): d.line((x,350,x+10,465),fill=(240,240,240),width=4)
        d.rectangle((0,0,W,36),fill=(15,24,32));d.text((12,4),names[n]+'  OFFLINE DEMO',fill='white',font=font)
        rgb=np.asarray(im)
        target=out/(names[n]+'.BMP');target.write_bytes(bmp_bytes(rgb,top_down=n%2==1,extra_header=16 if n==2 else 0))
        info=validate_bmp(target)
        packed=rgb[...,0].astype(np.uint64)*65536+rgb[...,1].astype(np.uint64)*256+rgb[...,2].astype(np.uint64)
        info['pixel_sum']=int(packed.sum())&0xffffffff;manifest.append(info)
        (refdir/(names[n]+'.hex')).write_text(''.join(f'{int(v):06x}\n' for v in packed.ravel()),encoding='ascii')
        for mode in range(6): Image.fromarray(reference(rgb,mode)).save(refdir/(names[n]+f'_mode{mode}.png'))
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    return manifest

def make_fixture(out, media_dir, mbr=False, broken='none'):
    """Sparse regular image file, not a disk/device. Real FAT32 geometry and fragmented chains."""
    out=Path(out)
    if out.suffix.lower()!='.img' or str(out).startswith(('\\\\.\\','/dev/')):
        raise ValueError('only a regular .img fixture file is accepted')
    total=131072; base=2048 if mbr else 0; reserved=32; fat_sectors=1024; fats=2
    data_lba=base+reserved+fats*fat_sectors
    fat=bytearray(fat_sectors*512)
    def link(c,next_c):struct.pack_into('<I',fat,c*4,next_c)
    link(0,0x0ffffff8);link(1,0x0fffffff);link(2,50000);link(50000,0x0fffffff);link(60000,0x0fffffff)
    boot=bytearray(512);boot[0:3]=b'\xeb\x58\x90';boot[3:11]=b'VEHMEDIA'
    struct.pack_into('<HBHBHHBHHHII',boot,11,512,1,reserved,2,0,0,0xf8,0,63,255,base,total)
    struct.pack_into('<IHHIHH',boot,36,fat_sectors,0,0,2,1,6)
    boot[64]=0x80;boot[66]=0x29;boot[71:82]=b'VEHMEDIA   ';boot[82:90]=b'FAT32   ';boot[510:512]=b'\x55\xaa'
    root0=bytearray(512);root1=bytearray(512)
    def entry(buf,i,name,cluster,size,deleted=False):
        off=i*32;stem,ext=name.split('.')
        buf[off:off+11]=stem.ljust(8).encode()+ext.ljust(3).encode();buf[off+11]=0x20
        if deleted:buf[off]=0xe5
        struct.pack_into('<H',buf,off+20,cluster>>16);struct.pack_into('<H',buf,off+26,cluster&65535);struct.pack_into('<I',buf,off+28,size)
    for i in range(16):entry(root0,i,f'T{i:07d}.TXT',0,0)
    entry(root1,0,'DELETE.BMP',60000,512,True);entry(root1,1,'BAD.BMP',60000,512)
    payloads=[]; meta=[]
    for i,path in enumerate(sorted(Path(media_dir).glob('*.BMP'))[:4]):
        data=path.read_bytes();blocks=(len(data)+511)//512
        if blocks>8192: raise ValueError('Fixture file exceeds 4 MiB cluster budget')
        chain=[3+i*8192+(j*17)%8192 for j in range(blocks)]
        for a,b in zip(chain,chain[1:]):link(a,b)
        link(chain[-1],0x0fffffff)
        if broken=='cycle' and i==0:link(chain[1],chain[0])
        if broken=='short' and i==0:link(chain[1],0x0fffffff)
        entry(root1,i+2,path.name,chain[0],len(data));payloads.append((data,chain))
        meta.append({'name':path.name,'clusters':blocks,'fragmented':True})
    with out.open('wb') as f:
        f.truncate((total+base)*512)
        def write_sector(lba,data):f.seek(lba*512);f.write(data.ljust(512,b'\0'))
        if mbr:
            partition=bytearray(512);partition[450]=0x0c;struct.pack_into('<II',partition,454,base,total);partition[510:512]=b'\x55\xaa';write_sector(0,partition)
        write_sector(base,boot)
        for n in range(fats):f.seek((base+reserved+n*fat_sectors)*512);f.write(fat)
        write_sector(data_lba,root0);write_sector(data_lba+50000-2,root1)
        write_sector(data_lba+60000-2,b'BM'+bytes(510))
        for data,chain in payloads:
            for j,c in enumerate(chain):write_sector(data_lba+c-2,data[j*512:(j+1)*512])
    out.with_suffix('.json').write_text(json.dumps({'mbr':mbr,'broken':broken,'files':meta},indent=2),encoding='utf-8')

def main():
    p=argparse.ArgumentParser();s=p.add_subparsers(dest='action',required=True)
    d=s.add_parser('demo');d.add_argument('--out',type=Path,default=ROOT/'assets'/'tf_card')
    c=s.add_parser('convert');c.add_argument('input',type=Path);c.add_argument('output',type=Path)
    c.add_argument('--native',action='store_true',help='Preserve source dimensions; FPGA performs scaling')
    v=s.add_parser('check');v.add_argument('files',nargs='+',type=Path)
    f=s.add_parser('fixture');f.add_argument('output',type=Path);f.add_argument('--media',type=Path,default=ROOT/'assets'/'tf_card');f.add_argument('--mbr',action='store_true');f.add_argument('--broken',choices=['none','cycle','short'],default='none')
    a=p.parse_args()
    if a.action=='demo':print(json.dumps(generate_demo(a.out),indent=2))
    elif a.action=='convert':
        if a.output.suffix.lower()!='.bmp':raise ValueError('output must end in .BMP')
        im=Image.open(a.input).convert('RGB')
        if a.native:
            if not (1<=im.width<=1024 and 1<=im.height<=768):raise ValueError('Native image exceeds FPGA dimension bounds')
            canvas=im
        else:
            im.thumbnail((W,H),Image.Resampling.LANCZOS)
            canvas=Image.new('RGB',(W,H));canvas.paste(im,((W-im.width)//2,(H-im.height)//2))
        a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_bytes(bmp_bytes(np.asarray(canvas)));print(validate_bmp(a.output))
    elif a.action=='check':
        for path in a.files:print(json.dumps(validate_bmp(path)))
    else:make_fixture(a.output,a.media,a.mbr,a.broken)
if __name__=='__main__':main()
