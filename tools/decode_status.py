"""Decode an actual STATUS response; accepts stdin or a quoted S:... argument."""
import argparse,json,sys
def decode(line):
    text=line.strip().removeprefix('S:')
    if len(text)!=48:raise ValueError('expected S: plus 48 hex characters')
    b=bytes.fromhex(text)
    if b[0]==0xa3:
        return {'schema':'A3','emergency':bool(b[1]&1),'night':bool(b[1]&2),
         'technical_view':bool(b[1]&4),'arrival':bool(b[1]&8),'station_index':b[2],
         'next_station_index':None if b[3]==255 else b[3],'menu_item':b[4],
         'playback_held':bool(b[5]),'media_ready':bool(b[6]),'media_state':b[7],
         'emergency_count':int.from_bytes(b[8:12],'big'),'recovery_count':int.from_bytes(b[12:16],'big'),
         'emergency_commit_cycles':int.from_bytes(b[16:20],'big'),
         'emergency_commit_ms':int.from_bytes(b[16:20],'big')/25000}
    if b[0]==0xa2:
        return {'schema':'A2','mean_gray':b[1],'media_retry_attempts':(b[2]>>4)&3,
         'menu_active':bool(b[2]&8),'continuous_audio':bool(b[2]&4),'wave_enabled':bool(b[2]&2),'ticker_enabled':bool(b[2]&1),
         'verified_slots':f'{b[3]&15:04b}','filesystem_state':b[4],
         'transition':bool(b[5]&32),'alpha':b[5]&31,'manual_threshold':b[6],'period_seconds':b[7],
         'display_frames':int.from_bytes(b[8:12],'big'),'load_cycles':int.from_bytes(b[12:16],'big'),
         'load_seconds':int.from_bytes(b[12:16],'big')/40000000,'sdram_read_timeouts':int.from_bytes(b[16:20],'big'),
         'skipped_files':int.from_bytes(b[20:22],'big'),'brightness':int.from_bytes(b[22:23],'big',signed=True),
         'volume':b[23]>>4}
    if b[0]!=0xa1:raise ValueError('unexpected firmware/schema version')
    return {'schema':'A1','edid_valid':bool(b[1]&128),'video_locked':bool(b[1]&64),'sd_initialized':bool(b[1]&32),
     'sdram_initialized':bool(b[1]&16),'scan_complete':bool(b[1]&8),'autoplay':bool(b[1]&4),
     'compare':bool(b[1]&2),'adaptive':bool(b[1]&1),'image_count':b[2]>>5,
     'mode':(b[2]>>2)&7,'image_index':b[2]&3,'media_error':f'{b[3]:02X}',
     'sd_error':f'{b[4]:02X}','cache_error':f'{b[5]:02X}','period_seconds':b[6],
     'volume':b[7]>>4,'write_checksum':int.from_bytes(b[8:12],'big'),
     'read_checksum':int.from_bytes(b[12:16],'big'),'pixel_underflows':int.from_bytes(b[16:20],'big'),
     'hdmi_ready_violations':int.from_bytes(b[20:24],'big')}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('line',nargs='?');a=p.parse_args()
 print(json.dumps(decode(a.line or sys.stdin.read()),indent=2))
