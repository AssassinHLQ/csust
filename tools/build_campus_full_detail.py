"""Unpack every original leaf into a single full-detail stream payload.

No representatives, covariance inflation, resampling or coordinate conversion.
The f32 records reproduce the q24 shader's leaf decoding. A single leaf cannot
be coarsened by SSE or the node budget. Output binaries remain derived assets.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def build(manifest_path, output_prefix):
    manifest_path, output_prefix = Path(manifest_path), Path(output_prefix)
    source = json.loads(manifest_path.read_text(encoding='utf-8'))
    if source['record_layout'] != 'q24' or source['sh_degree'] != 0:
        raise ValueError('Expected the campus q24/SH0 pack')
    table = np.asarray(source['node_table'], dtype=np.float64).reshape(-1, 16)
    leaves = table[np.all(table[:, 8:] < 0, axis=1)]
    count = int(source['source_splats'])
    if int(leaves[:, 6].sum()) != count or not np.array_equal(leaves[:, 6], leaves[:, 7]):
        raise ValueError('Leaves do not preserve every source point')
    output_bin = Path(str(output_prefix) + '.nodes.bin')
    output_manifest = Path(str(output_prefix) + '.manifest.json')
    input_bin = manifest_path.parent / Path(source['nodes_bin']).name
    if input_bin.resolve() == output_bin.resolve():
        raise ValueError('Output must not overwrite the source stream pack')
    output_bin.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    with input_bin.open('rb') as reader, output_bin.open('wb') as writer:
        for node in leaves:
            n = int(node[6])
            reader.seek(int(node[5]))
            raw = reader.read(n * 24)
            if len(raw) != n * 24:
                raise ValueError('Truncated source leaf')
            records = np.frombuffer(raw, dtype=np.uint8).reshape(n, 24)
            positions = records[:, :6].copy().view('<i2').reshape(n, 3)
            # Match the projection shader's float32 arithmetic.
            positions = positions.astype(np.float32) * (np.float32(node[3]) / np.float32(32767))
            positions += node[:3].astype(np.float32)
            bf16 = records[:, 8:20].copy().view('<u2').reshape(n, 6)
            covariance = (bf16.astype('<u4') << 16).view('<f4')
            out = np.zeros((n, 52), dtype=np.uint8)
            out[:, :12] = positions.view(np.uint8).reshape(n, 12)
            out[:, 12:14] = records[:, 6:8]
            out[:, 16:40] = covariance.view(np.uint8).reshape(n, 24)
            out[:, 48:52] = records[:, 20:24]
            payload = out.tobytes()
            writer.write(payload)
            digest.update(payload)
    root = table[int(source['root'])].tolist()
    root[4:8] = [0, 0, count, count]
    root[8:] = [-1] * 8
    result = dict(source)
    result.update(record_layout='f32', stride_bytes=52, stride_words=13,
                  node_cap=count, leaf_cap=count, root=0, node_count=1,
                  leaf_count=1, branch_count=0, max_depth=0,
                  stored_splats=count, nodes_bin=output_bin.name,
                  nodes_bytes=output_bin.stat().st_size, node_table=root,
                  lod={'mode': 'disabled'})
    result['source'] = dict(source.get('source', {}),
                            full_detail_from=manifest_path.name,
                            lod='disabled: every original leaf point; no representatives',
                            payload_sha256=digest.hexdigest())
    output_manifest.write_text(json.dumps(result, separators=(',', ':')), encoding='utf-8')
    print(json.dumps({'points': count, 'bytes': output_bin.stat().st_size,
                      'leaves_preserved': len(leaves), 'sha256': digest.hexdigest()}))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'splatdata/campus_stream/campus.manifest.json')
    parser.add_argument('--out', type=Path, default=ROOT / 'splatdata/campus_stream/campus_full')
    args = parser.parse_args()
    build(args.manifest, args.out)
