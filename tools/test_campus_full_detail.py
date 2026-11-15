"""Check full-detail conversion against scalar shader-layout decoding."""
import json
import struct
import tempfile
import unittest
from pathlib import Path

from build_campus_full_detail import build


class FullDetailTests(unittest.TestCase):
    def test_original_leaves_only_and_exact_decode(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            records = []
            for xyz in [(-32767, 0, 32767), (123, -456, 789), (0, 0, 0)]:
                records.append(struct.pack('<hhhBB6H4B', *xyz, 197, 0,
                                           0x3f80, 0xbf00, 0x3d00, 0x4000, 0, 0x3e80,
                                           255, 12, 127, 0))
            table = [0, 0, 0, 20, 100, 0, 1, 3, 1, 2, -1, -1, -1, -1, -1, -1,
                     -4, 2, 0, 4, 0, 24, 2, 2, *([-1] * 8),
                     8, -3, 5, 2, 0, 72, 1, 1, *([-1] * 8)]
            source = {'record_layout': 'q24', 'sh_degree': 0, 'sh_scale': .05,
                      'root': 0, 'source_splats': 3, 'node_table': table,
                      'nodes_bin': 'source.nodes.bin'}
            (folder / 'source.nodes.bin').write_bytes(b'B' * 24 + b''.join(records))
            manifest = folder / 'source.manifest.json'
            manifest.write_text(json.dumps(source), encoding='utf-8')
            prefix = folder / 'full'
            result = build(manifest, prefix)
            payload = (folder / 'full.nodes.bin').read_bytes()
            self.assertEqual(len(payload), 3 * 52)
            self.assertEqual(result['node_count'], 1)
            self.assertEqual(result['leaf_count'], 1)
            self.assertEqual(result['branch_count'], 0)
            self.assertEqual(result['nodes_bytes'], len(payload))
            self.assertEqual(result['node_table'][6:8], [3, 3])
            for i, raw in enumerate(records):
                centre, half = ((-4, 2, 0), 4) if i < 2 else ((8, -3, 5), 2)
                expected_position = [centre[j] + q * half / 32767
                                     for j, q in enumerate(struct.unpack_from('<3h', raw))]
                actual_position = struct.unpack_from('<3f', payload, i * 52)
                for expected, actual in zip(expected_position, actual_position):
                    self.assertAlmostEqual(expected, actual, places=6)
                expected_covariance = [struct.unpack('<f', struct.pack('<I', b << 16))[0]
                                       for b in struct.unpack_from('<6H', raw, 8)]
                self.assertEqual(list(struct.unpack_from('<6f', payload, i * 52 + 16)), expected_covariance)
                self.assertEqual(payload[i * 52 + 12:i * 52 + 14], raw[6:8])
                self.assertEqual(payload[i * 52 + 48:(i + 1) * 52], raw[20:24])

    def test_reject_incomplete_leaf_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            source = {'record_layout': 'q24', 'sh_degree': 0, 'source_splats': 2,
                      'node_table': [0, 0, 0, 1, 0, 0, 1, 2, *([-1] * 8)]}
            manifest = folder / 'source.manifest.json'
            manifest.write_text(json.dumps(source), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'every source point'):
                build(manifest, folder / 'full')


if __name__ == '__main__':
    unittest.main()
