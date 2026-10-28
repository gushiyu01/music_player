"""Generate the project's simple waveform icon with Python's standard library."""
from pathlib import Path
import json
import math
import struct
import zlib

root = Path(__file__).resolve().parents[1]

def png(size):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            px, py = (x + .5) / size, (y + .5) / size
            distance = math.hypot(px - .5, py - .5)
            color = (16, 20, 17)
            if distance < .36:
                color = (40, 56, 40)
            for line, height in enumerate([.12, .25, .39, .27, .14]):
                cx = .3 + line * .1
                dy = max(0, abs(py - .5) - height / 2)
                if math.hypot(px - cx, dy) < .024:
                    color = (189, 231, 162)
            raw.extend(color)
    def block(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return b'\x89PNG\r\n\x1a\n' + block(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) + block(b'IDAT', zlib.compress(raw, 9)) + block(b'IEND', b'')

for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    (root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png').write_bytes(png(size))
icons = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((icons / 'Contents.json').read_text())['images']:
    if 'filename' in item:
        size = round(float(item['size'].split('x')[0]) * float(item['scale'].removesuffix('x')))
        (icons / item['filename']).write_bytes(png(size))
print('Generated Android and iOS waveform icons.')
