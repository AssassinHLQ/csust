"""Build the campus q24/SH0 stream pack in the existing collision world frame.

Requires numpy, scipy, Pillow and the sibling godot-gsplat-stream tools. Never
re-centres the scan or arranges chunks on a shelf. Output is a derived local
asset; export_presets.cfg includes it in the game package.
"""
import argparse
import hashlib
import json
import subprocess
import sys
import types
import zipfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugin', type=Path, default=ROOT.parent / 'godot-gsplat-stream')
    parser.add_argument('--work', type=Path, default=ROOT / '_tools/_tmp/campus_stream_build')
    parser.add_argument('--out', type=Path, default=ROOT / 'splatdata/campus_stream/campus')
    args = parser.parse_args()
    plugin_tools = args.plugin.resolve() / 'tools'
    for name in ['sog_to_columns.py', 'ply_to_packed.py', 'build_stream_pack.py']:
        if not (plugin_tools / name).is_file():
            parser.error(f'Missing plugin builder: {plugin_tools / name}')
    sys.path.insert(0, str(plugin_tools))
    import sog_to_columns as sog
    import ply_to_packed as packed

    # Fine chunks reference an external higher-band palette. This pack stores
    # DC colour only, so the unused SH block must not be decoded from each ZIP.
    class DCZip(zipfile.ZipFile):
        def read(self, name, *positional, **keyword):
            data = super().read(name, *positional, **keyword)
            if name == 'meta.json':
                meta = json.loads(data)
                meta.pop('shN', None)
                return json.dumps(meta).encode()
            return data

    sog.zipfile = types.SimpleNamespace(ZipFile=DCZip)
    source_path = ROOT / 'splatdata/campus_sog/chunks.json'
    manifest = json.loads(source_path.read_text(encoding='utf-8-sig'))
    basis = np.array(manifest['frame']['axes'], dtype=np.float32).T
    origin = np.array(manifest['frame']['origin'], dtype=np.float32)
    args.work.mkdir(parents=True, exist_ok=True)
    raw = args.work / 'campus.raw'
    if raw.exists():
        parser.error(f'Work file already exists; choose a fresh --work directory: {raw}')
    scale = 0.0
    for chunk in manifest['chunks']:
        with zipfile.ZipFile(ROOT / chunk['sog']) as archive:
            meta = json.loads(archive.read('meta.json'))
            scale = max(scale, float(np.abs(meta['sh0']['codebook']).max()) / 127)
    minimum = np.full(3, np.inf)
    maximum = -minimum
    count = 0
    with raw.open('xb') as handle:
        for chunk in manifest['chunks']:
            data = sog.decode_sog(str(ROOT / chunk['sog']))
            if data['n'] != chunk['points']:
                raise ValueError(f"Source count differs: {chunk['sog']}")
            qx, qy, qz, qw = data['rot']
            cov = packed.covariance_from(tuple(data['scale'].T), (qw, qx, qy, qz))
            matrices = cov[:, [[0, 1, 2], [1, 3, 4], [2, 4, 5]]]
            matrices = basis @ matrices @ basis.T
            cov = np.ascontiguousarray(matrices[:, [0, 0, 0, 1, 1, 2], [0, 1, 2, 1, 2, 2]])
            positions = data['pos'] @ basis.T + origin
            batch = dict(n=data['n'], pos=positions, cov=cov,
                         opacity=data['opacity'], sh=data['sh'])
            records, info = packed.build_packed(batch, 0, np.zeros(3, dtype=np.float32), sh_scale=scale)
            handle.write(records.tobytes())
            minimum = np.minimum(minimum, positions.min(axis=0))
            maximum = np.maximum(maximum, positions.max(axis=0))
            count += data['n']
            print(f"{chunk['name']}: {count:,} points", flush=True)
    if count != sum(chunk['points'] for chunk in manifest['chunks']):
        raise ValueError('Incomplete source scan')
    info.update(count=count, degree=0, sh_scale=scale,
                aabb_min=minimum.tolist(), aabb_size=(maximum-minimum).tolist())
    Path(str(raw) + '.manifest.json').write_text(json.dumps(info, indent=2), encoding='utf-8')
    subprocess.run([sys.executable, str(plugin_tools / 'build_stream_pack.py'), str(raw),
                    '--out', str(args.out.resolve()), '--node-cap', '16384',
                    '--leaf-cap', '16384', '--quantize', 'q24', '--alpha-power', '1'], check=True)
    output_manifest = Path(str(args.out) + '.manifest.json')
    output_bin = Path(str(args.out) + '.nodes.bin')
    result = json.loads(output_manifest.read_text(encoding='utf-8'))
    result['nodes_bin'] = output_bin.name
    result['source'] = {'frame': 'campus collision world coordinates; identity stream transform',
                        'chunks_sha256': sha256(source_path), 'colour': 'SH0 only',
                        'payload_sha256': sha256(output_bin)}
    output_manifest.write_text(json.dumps(result, separators=(',', ':')), encoding='utf-8')
    print(json.dumps(result['source'], indent=2), flush=True)


if __name__ == '__main__':
    main()
