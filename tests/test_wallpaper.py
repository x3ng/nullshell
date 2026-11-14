#!/usr/bin/env python3
"""Bounded assets, fit-only updates, atomic failure and cleanup; synthetic PNGs."""
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib


def png(red, green, blue, width=64, height=48):
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    pixels = b''.join(b'\0' + bytes((red, green, blue)) * width for _ in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))


def main(helper):
    with tempfile.TemporaryDirectory(prefix='ns-wall-', dir='/tmp') as directory:
        root = Path(directory)
        shared = root / 'relocated shared'
        shared.mkdir()
        descriptor = shared / 'wallpaper.json'
        source = root / 'image with spaces.png'
        unrelated = shared / 'unrelated.txt'
        unrelated.write_text('must survive')

        def export(path, fit='cover', success=True):
            result = subprocess.run([helper, 'wallpaper-export', str(descriptor)],
                                    input=json.dumps(dict(version=1, source=str(path), fit=fit)),
                                    text=True, capture_output=True, umask=0o077)
            assert (result.returncode == 0) == success, result.stderr
            return json.loads(descriptor.read_text()) if descriptor.exists() else None

        source.write_bytes(png(20, 40, 80))
        first = export(source)
        asset = shared / first['image']
        stamp = asset.stat().st_mtime_ns
        assert asset.read_bytes() == source.read_bytes()
        assert asset.stat().st_mode & 0o777 == 0o640
        assert descriptor.stat().st_mode & 0o777 == 0o640
        second = export(source, 'contain')
        assert second['image'] == first['image'] and second['revision'] == first['revision']
        assert asset.stat().st_mtime_ns == stamp, 'Fit change recopied image'
        for i in range(12):
            source.write_bytes(png(30 + i, 60, 90))
            current = export(source)
            assert len(list(shared.glob('wallpaper-*.img'))) <= 2
            assert (shared / current['image']).read_bytes() == source.read_bytes()
        # Corrupt metadata must not poison a later valid publication.
        damaged = dict(current, revision="invalid", version=2)
        descriptor.write_text(json.dumps(damaged))
        repaired = export(source)
        assert repaired['version'] == 1 and repaired['revision'] != 'invalid'
        before = descriptor.read_bytes()
        for invalid in ('missing.png', 'invalid.txt'):
            bad = root / invalid
            if invalid.endswith('.txt'):
                bad.write_text('not an image')
            export(bad, success=False)
            assert descriptor.read_bytes() == before
        huge = root / 'huge.png'
        with huge.open('wb') as f:
            f.truncate(16 * 1024 * 1024 + 1)
        export(huge, success=False)
        assert descriptor.read_bytes() == before
        pipe = root / 'pipe'
        os.mkfifo(pipe)
        export(pipe, success=False)
        # Simulate a killed export. The next publication replaces bounded pending data.
        (shared / '.wallpaper.pending').write_bytes(b'incomplete')
        cleared = export('')
        assert cleared['image'] is None and cleared['revision'] == ''
        assert not list(shared.glob('wallpaper-*.img'))
        assert not (shared / '.wallpaper.pending').exists()
        assert unrelated.read_text() == 'must survive'
        assert source.exists()
    print('Wallpaper limits, fit-only updates, fixed slots, failed publication and cleanup passed')

if __name__ == '__main__':
    main(str(Path(sys.argv[1]).resolve()))
