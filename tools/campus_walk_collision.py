"""Build a continuous walking surface and retain substantial scanned obstacles.

Only measured 0.5 m support cells become terrain; the scan outline and missing
regions stay open. Small detached scan protrusions are omitted from collision.
The resulting faces are already in Godot world coordinates.
"""
import argparse
import json
import subprocess
from pathlib import Path

import numpy as np
from scipy import ndimage
import trimesh

from campus_splattransform_collision import clip_triangles

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = np.array([-288., -564.])
STEP = .5


def sample(points, height):
    coords = np.stack(((points[..., 2] + 564) / STEP,
                       (points[..., 0] + 288) / STEP)).reshape(2, -1)
    return ndimage.map_coordinates(height, coords, order=1, mode='nearest').reshape(points.shape[:-1])


def terrain(tile, height, valid):
    lo, hi = np.array(tile['core_min_xz']), np.array(tile['core_max_xz'])
    zz, xx = np.where(valid)
    centers = ORIGIN + np.c_[xx, zz] * STEP
    selected = ((centers + STEP / 2 >= lo) & (centers - STEP / 2 <= hi)).all(1)
    centers = centers[selected]
    corners = []
    for dx, dz in [(-.25, -.25), (.25, -.25), (.25, .25), (-.25, .25)]:
        p = np.c_[centers[:, 0] + dx, np.zeros(len(centers)), centers[:, 1] + dz]
        p[:, 1] = sample(p, height)
        corners.append(p)
    a, b, c, d = corners
    faces = np.concatenate((np.stack((a, c, b), 1), np.stack((a, d, c), 1)))
    for axis, lower, upper in zip((0, 2), lo, hi):
        faces = clip_triangles(faces, axis, lower, True)
        faces = clip_triangles(faces, axis, upper, False)
    return faces


def obstacles(triangles, height, valid, tile):
    normals = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    steep = np.abs(normals[:, 1]) < np.linalg.norm(normals, axis=1) * .35
    # A trunk or wall has a vertical run of scanned surface. Low disconnected
    # vegetation and shell spikes do not become knee-height invisible walls.
    profile = np.zeros(height.shape, dtype=np.uint8)
    vertical = triangles[steep]
    points = np.concatenate((vertical[:, 0], vertical[:, 1], vertical[:, 2],
                             vertical.mean(1), (vertical[:, 0] + vertical[:, 1]) / 2,
                             (vertical[:, 1] + vertical[:, 2]) / 2,
                             (vertical[:, 2] + vertical[:, 0]) / 2))
    level = np.floor((points[:, 1] - sample(points, height) - .2) / .3).astype(int)
    xx = np.rint((points[:, 0] + 288) / STEP).astype(int)
    zz = np.rint((points[:, 2] + 564) / STEP).astype(int)
    good = (level >= 0) & (level < 8) & (xx >= 0) & (xx < 1153) & (zz >= 0) & (zz < 979)
    np.bitwise_or.at(profile, (zz[good], xx[good]), (1 << level[good]).astype('u1'))
    # Simplified walls have long triangles: seven samples per triangle can
    # leave metre-wide holes. Rasterize horizontal height contours at <=20 cm
    # intervals, so every crossed structural column receives its height bits.
    relative_vertical = vertical[:, :, 1] - sample(vertical, height)
    for band in range(8):
        signed = relative_vertical - (.2 + (band + .5) * .3)
        above = signed >= 0
        for positive in (1, 2):
            ids = np.flatnonzero(above.sum(1) == positive)
            if not len(ids):
                continue
            tri, values = vertical[ids], signed[ids]
            corner = np.argmax(values >= 0, axis=1) if positive == 1 else np.argmin(values >= 0, axis=1)
            row = np.arange(len(ids))
            a, b, c = (tri[row, (corner + k) % 3] for k in range(3))
            va, vb, vc = (values[row, (corner + k) % 3] for k in range(3))
            begin = a + (va / (va - vb))[:, None] * (b - a)
            end = a + (va / (va - vc))[:, None] * (c - a)
            steps = np.maximum(1, np.ceil(np.linalg.norm((end - begin)[:, (0, 2)], axis=1) / .2).astype(int))
            count_points = steps + 1
            segments = np.repeat(np.arange(len(steps)), count_points)
            offsets = np.cumsum(count_points) - count_points
            fraction = (np.arange(count_points.sum()) - np.repeat(offsets, count_points)) / steps[segments]
            points = begin[segments] + fraction[:, None] * (end - begin)[segments]
            xx = np.rint((points[:, 0] + 288) / STEP).astype(int)
            zz = np.rint((points[:, 2] + 564) / STEP).astype(int)
            good = (xx >= 0) & (xx < 1153) & (zz >= 0) & (zz < 979)
            np.bitwise_or.at(profile, (zz[good], xx[good]), np.uint8(1 << band))
    count = np.unpackbits(profile[..., None], axis=2).sum(2)
    strong = (count >= 3) & ((profile & 0b11111000) != 0)
    relative = triangles[:, :, 1] - sample(triangles, height)
    # The lower wall/trunk zone uses solid closed bases rather than hollow
    # native shells. A capsule must never be able to enter the shell's void.
    clearance = np.full(len(triangles), 2.6)
    signed = relative - clearance[:, None]
    # Outside measured terrain retain native geometry, including lower layers.
    coords = np.stack(((triangles[..., 2] + 564) / STEP,
                       (triangles[..., 0] + 288) / STEP)).reshape(2, -1)
    supported = ndimage.map_coordinates(valid.astype(float), coords, order=1,
                                        mode='constant', cval=0).reshape(signed.shape) > .99
    trim = supported.all(1)
    above = signed >= 0
    result = [triangles[~trim | above.all(1)]]
    for count in (1, 2):
        ids = np.flatnonzero(trim & (above.sum(1) == count))
        if not len(ids):
            continue
        tri, values = triangles[ids], signed[ids]
        corner = np.argmax(values >= 0, axis=1) if count == 1 else np.argmin(values >= 0, axis=1)
        row = np.arange(len(ids))
        a, b, c = (tri[row, (corner + k) % 3] for k in range(3))
        va, vb, vc = (values[row, (corner + k) % 3] for k in range(3))
        ab = a + (va / (va - vb))[:, None] * (b - a)
        ac = a + (va / (va - vc))[:, None] * (c - a)
        if count == 1:
            result.append(np.stack((a, ab, ac), 1))
        else:
            result.extend((np.stack((ab, b, c), 1), np.stack((ab, c, ac), 1)))
    faces = np.concatenate(result).astype('<f4')
    mesh = trimesh.Trimesh(vertices=faces.reshape(-1, 3),
                           faces=np.arange(faces.size // 3).reshape(-1, 3), process=True)
    mesh.update_faces(mesh.nondegenerate_faces())
    mesh.remove_unreferenced_vertices()
    retained, removed = [], 0
    for group in mesh.split(only_watertight=False):
        extent = group.extents
        # Preserve tall trunks and broad walls/cars; omit small scan debris.
        substantial = extent[1] >= 1. or max(extent[0], extent[2]) >= 2.
        if not substantial:
            removed += len(group.faces)
            continue
        kept = group.triangles
        retained.append(kept)
    bases = solid_bases(tile, height, valid, strong, profile)
    retained.append(bases)
    return np.concatenate(retained), removed


def solid_bases(tile, height, valid, strong, profile):
    solid = (strong | ndimage.binary_closing(strong, structure=np.ones((3, 3)))) & valid
    zz, xx = np.indices(solid.shape)
    x, z = ORIGIN[0] + xx * STEP, ORIGIN[1] + zz * STEP
    lo, hi = np.array(tile['core_min_xz']), np.array(tile['core_max_xz'])
    solid &= (x + .25 > lo[0]) & (x - .25 < hi[0]) & (z + .25 > lo[1]) & (z - .25 < hi[1])
    # Fill only narrow gaps between structural columns, with neighbouring
    # measured heights. Preserve a low wall's height instead of making it tall.
    lookup = np.array([int(v).bit_length() for v in range(256)])
    top = ndimage.maximum_filter(.2 + .3 * lookup[profile], size=3)
    elevated = height + top
    indices = np.array([[0,2,1],[0,3,2],[4,5,6],[4,6,7],
                        [0,1,5],[0,5,4],[1,2,6],[1,6,5],
                        [2,3,7],[2,7,6],[3,0,4],[3,4,7]])
    result = []
    for row, col in np.argwhere(solid):
        if not solid[row, col]:
            continue
        end_x = col + 1
        while end_x < solid.shape[1] and solid[row, end_x]:
            end_x += 1
        end_z = row + 1
        while end_z < solid.shape[0] and solid[end_z, col:end_x].all():
            end_z += 1
        solid[row:end_z, col:end_x] = False
        x0, z0 = np.maximum(lo, ORIGIN + np.array([col, row]) * STEP - .25)
        x1, z1 = np.minimum(hi, ORIGIN + np.array([end_x-1, end_z-1]) * STEP + .25)
        bottom = float(height[row:end_z, col:end_x].min()) - .1
        upper = float(elevated[row:end_z, col:end_x].max())
        vertices = np.array([[x0,bottom,z0],[x1,bottom,z0],[x1,bottom,z1],[x0,bottom,z1],
                             [x0,upper,z0],[x1,upper,z0],[x1,upper,z1],[x0,upper,z1]])
        result.append(vertices[indices])
    return np.concatenate(result) if result else np.empty((0,3,3))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--heightfield', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--tile', action='append')
    args = parser.parse_args()
    if args.out.exists():
        raise FileExistsError(args.out)
    manifest = json.loads((args.source / 'manifest.json').read_text(encoding='utf-8'))
    raw = np.fromfile(args.heightfield, dtype='<f4').reshape(979, 1153)
    valid = np.isfinite(raw)
    if not valid.any():
        raise ValueError('No measured ground support')
    _, nearest = ndimage.distance_transform_edt(~valid, return_indices=True)
    filled = raw[tuple(nearest)]
    height = ndimage.gaussian_filter(ndimage.median_filter(filled, size=7, mode='nearest'),
                                    sigma=2., mode='nearest')
    args.out.mkdir(parents=True)
    height.astype('<f4').tofile(args.out / 'terrain_height.f32')
    valid.astype('u1').tofile(args.out / 'terrain_support.u8')
    reports = []
    for tile in manifest['tiles']:
        if args.tile and tile['name'] not in args.tile:
            continue
        source = np.fromfile(args.source / (tile['name'] + '.faces.f32'), dtype='<f4').reshape(-1, 3, 3)
        detail, removed = obstacles(source, height, valid, tile)
        floor = terrain(tile, height, valid)
        faces = np.concatenate((floor, detail))
        mesh = trimesh.Trimesh(vertices=faces.reshape(-1, 3),
                               faces=np.arange(faces.size // 3).reshape(-1, 3), process=True)
        mesh.update_faces(mesh.nondegenerate_faces())
        mesh.remove_unreferenced_vertices()
        prefix = args.out / tile['name']
        mesh.vertices.astype('<f4').tofile(prefix.with_suffix('.vertices.f32'))
        mesh.faces.astype('<u4').tofile(prefix.with_suffix('.indices.u32'))
        with prefix.with_suffix('.simplify.log').open('w', encoding='utf-8') as log:
            subprocess.run(['node', str(ROOT / 'tools/simplify_campus_collision.mjs'),
                            str(args.runtime), str(prefix), '.05'], check=True,
                           stdout=log, stderr=subprocess.STDOUT,
                           creationflags=subprocess.CREATE_NO_WINDOW)
        simplified = json.loads(prefix.with_suffix('.simplification.json').read_text())
        report = dict(tile, triangles=simplified['simplified_triangles'],
                      omitted_small_detail_triangles=removed,
                      walking_surface_triangles_before_simplification=len(floor))
        reports.append(report)
        print(json.dumps(report), flush=True)
    delta = np.abs(height[valid] - raw[valid])
    manifest.update(tiles=reports, triangles=sum(t['triangles'] for t in reports),
                    partial=bool(args.tile), walking_surface={
                        'grid_m': STEP, 'median_cells': 7, 'gaussian_sigma_cells': 2.,
                        'support': 'measured cells only, no missing-region fill',
                        'obstacles': 'closed 0.5m structural column bases; hollow native shells omitted below 2.6m; native upper geometry retained',
                        'simplification_error_m': .05,
                        'structural_grid_m': .5, 'structural_contour_spacing_m': .2,
                        'native_shell_clearance_m': 2.6,
                        'sample_height_difference_m': {str(q): float(np.percentile(delta, q))
                                                       for q in [50, 90, 95, 99, 100]}})
    (args.out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
