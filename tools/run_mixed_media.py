"""Build bit-exact mixed-size references and test FAT32 -> BMP -> scaler together.

Only regular local fixture files are written. No card/device is touched.
The reference parses stored BMP row order instead of relying on image-library
resampling defaults: Q12 align-corners coordinates, Q8 coefficients and two
rounded 1-D interpolations, matching the documented fixed-point convention.
"""
from pathlib import Path
import hashlib
import json
import struct

import numpy as np
from PIL import Image

from media_tools import ROOT, make_fixture
from run_sim import run

OUT_W, OUT_H = 640, 480


def scale_reference(path: Path):
    data = path.read_bytes()
    magic, declared_size, _, _, offset = struct.unpack_from('<2sIHHI', data)
    dib, w, signed_h, planes, bits, compression = struct.unpack_from('<IiiHHI', data, 14)
    h = abs(signed_h)
    stride = (w * 3 + 3) & ~3
    if not (magic == b'BM' and 1 <= w <= 1024 and 1 <= h <= 768
            and 40 <= dib <= 4096 and planes == 1 and bits == 24
            and compression == 0 and 14 + dib <= offset <= 4096
            and offset + stride * h <= declared_size <= len(data) <= 4194304):
        raise ValueError(f'Unsupported BMP fixture: {path}')
    stored = np.frombuffer(data, np.uint8, count=stride * h, offset=offset)
    source = stored.reshape(h, stride)[:, :w * 3].reshape(h, w, 3)[..., ::-1].astype(np.int32)
    if w * OUT_H >= h * OUT_W:
        fit_w, fit_h = OUT_W, max(1, h * OUT_W // w)
    else:
        fit_w, fit_h = max(1, w * OUT_H // h), OUT_H
    top_down = signed_h < 0
    pad_x = (OUT_W - fit_w) // 2
    pad_y = (OUT_H - fit_h + (0 if top_down else 1)) // 2

    def coordinates(source_size, output_size):
        step = ((source_size - 1) << 12) // (output_size - 1) if output_size > 1 else 0
        coordinate = np.arange(output_size, dtype=np.int64) * step
        if output_size > 1:
            coordinate[-1] = (source_size - 1) << 12
        lower = coordinate >> 12
        upper = np.minimum(lower + 1, source_size - 1)
        weight = (coordinate & 4095) >> 4
        return lower, upper, weight.astype(np.int32)

    x0, x1, fx = coordinates(w, fit_w)
    y0, y1, fy = coordinates(h, fit_h)
    wx, wy = fx[None, :, None], fy[:, None, None]
    a = (source[y0[:, None], x0[None, :]] * (256 - wx)
         + source[y0[:, None], x1[None, :]] * wx + 128) >> 8
    b = (source[y1[:, None], x0[None, :]] * (256 - wx)
         + source[y1[:, None], x1[None, :]] * wx + 128) >> 8
    fitted = ((a * (256 - wy) + b * wy + 128) >> 8).astype(np.uint8)
    canvas = np.zeros((OUT_H, OUT_W, 3), np.uint8)
    canvas[pad_y:pad_y + fit_h, pad_x:pad_x + fit_w] = fitted
    if not top_down:
        canvas = canvas[::-1]
    packed = ((canvas[..., 0].astype(np.uint64) << 16)
              | (canvas[..., 1].astype(np.uint64) << 8) | canvas[..., 2].astype(np.uint64))
    info = {'file': path.name, 'source_width': w, 'source_height': h,
            'scaled_width': fit_w, 'scaled_height': fit_h, 'top_down': top_down,
            'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'expected_rgb24_sum': int(packed.sum()) & 0xffffffff}
    return canvas, packed, info


def main():
    media = ROOT / 'assets/tf_card_extended'
    references = ROOT / 'assets/reference_extended'
    references.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((media / 'manifest.json').read_text(encoding='utf-8'))
    existing = {entry['file']: entry for entry in manifest['files']}
    results = []
    for source in sorted(media.glob('*.BMP')):
        canvas, packed, info = scale_reference(source)
        expected = existing[source.name]['expected_rgb24_sum']
        if info['expected_rgb24_sum'] != expected:
            raise AssertionError(f'{source.name}: reference sum {info["expected_rgb24_sum"]:08x} '
                                 f'differs from media manifest {expected:08x}')
        (references / (source.stem + '.hex')).write_text(
            ''.join(f'{int(pixel):06x}\n' for pixel in packed.ravel()), encoding='ascii')
        Image.fromarray(canvas).save(references / (source.stem + '.png'))
        results.append(info)
    if len(results) != 4:
        raise AssertionError('Exactly four mixed-resolution sources required')
    (references / 'manifest.json').write_text(json.dumps(
        {'coordinate_format': 'Q12 align corners; Q8 fractional weights; two rounded lerps',
         'output_width': OUT_W, 'output_height': OUT_H, 'files': results}, indent=2), encoding='utf-8')
    fixture = ROOT / 'assets/mixed_fat32.img'
    make_fixture(fixture, media, mbr=True)
    report = run('tb_media_mixed', sources=['rtl/fat32_media.v', 'rtl/bmp_stream.v'])
    (ROOT / 'build/sim/mixed_media_result.json').write_text(json.dumps(
        {'simulation': report, 'fixture': str(fixture), 'reference_files': results}, indent=2), encoding='utf-8')
    print(json.dumps({'passed': report['passed'], 'pixels_verified': 4 * OUT_W * OUT_H,
                      'source_sizes': [[x['source_width'], x['source_height']] for x in results]}))


if __name__ == '__main__':
    main()
