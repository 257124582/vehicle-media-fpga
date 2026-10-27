"""Validate actual four-image UART self-test evidence against supplied BMP sums."""
from pathlib import Path
import argparse,json
from decode_status import decode
ROOT=Path(__file__).resolve().parents[1]
def check(path):
    records=json.loads(Path(path).read_text(encoding='utf-8-sig'))
    if isinstance(records,dict):records=[records]
    manifest=json.loads((ROOT/'assets/tf_card/manifest.json').read_text(encoding='utf-8'))
    sums={i:item['pixel_sum'] for i,item in enumerate(manifest)}
    seen={}
    for record in records:
        if record['command']!='STATUS':
            assert record['response']=='OK',record
            continue
        status=decode(record['response']);index=status['image_index']
        assert status['sd_initialized'] and status['sdram_initialized'] and status['scan_complete'],status
        assert status['image_count']==4,status
        assert all(status[k]=='00' for k in ['sd_error','media_error','cache_error']),status
        assert status['pixel_underflows']==0 and status['hdmi_ready_violations']==0,status
        assert status['write_checksum']==sums[index],status
        assert status['read_checksum']==sums[index],status
        seen[index]=status
    assert set(seen)==set(sums),'the log must contain all four image slots'
    return {'passed':True,'source_log':str(Path(path).resolve()),'images':seen,
            'scope':'real SD load and SDRAM checksums through UART; HDMI receiver not tested'}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('log');p.add_argument('--output');a=p.parse_args()
    result=check(a.log)
    if a.output:Path(a.output).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=True))
