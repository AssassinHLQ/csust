"""Build scan-outline guards and a supported access bridge in campus world space.

Inputs are downward ray samples of the actual collision candidate, with 0.5 m
spacing and origin (-288,-564). Missing samples stay missing. Guards add only
vertical faces; the bridge is the sole new horizontal infrastructure.
"""
import argparse
import heapq
import json
import math
from pathlib import Path

import numpy as np
from scipy import ndimage


def bridge_path(top, target, width):
    radius = math.ceil((width * .5 + .15) / .5)
    clearance = ndimage.maximum_filter(np.nan_to_num(top, nan=-100), size=radius * 2 + 1)
    start = (10, 0, -70)
    goal = (int(target[0]), round(target[1] * 2), int(target[2]))

    def lower(x, z):
        ix, iz = round((x + 288) * 2), round((z + 564) * 2)
        return float(clearance[iz, ix]) if 0 <= ix < 1153 and 0 <= iz < 979 else -100

    def heuristic(n):
        return math.hypot(n[0] - goal[0], n[2] - goal[2]) + abs(n[1] - goal[1]) * .3

    queue, cost, prev = [(heuristic(start), 0., start)], {start: 0.}, {}
    sx, sz = -2 if goal[0] < start[0] else 2, -2 if goal[2] < start[2] else 2
    while queue:
        _, g, n = heapq.heappop(queue)
        if g > cost[n]:
            continue
        if n == goal:
            path = [n]
            while n in prev:
                n = prev[n]
                path.append(n)
            points = np.array([[x, y * .5, z] for x, y, z in reversed(path)], dtype=float)
            break
        x, y, z = n
        for dx, dz in [(sx, 0), (0, sz), (sx, sz)]:
            xx, zz = x + dx, z + dz
            if not (min(goal[0], start[0]) <= xx <= max(goal[0], start[0]) and
                    min(goal[2], start[2]) <= zz <= max(goal[2], start[2])):
                continue
            bottom = lower(xx, zz) + .12
            for dy in [0, 1, -1]:
                yy = y + dy
                if not (-12 <= yy <= 36) or yy * .5 < bottom:
                    continue
                m = (xx, yy, zz)
                c = g + math.hypot(dx, dz) + abs(dy) * .15 + max(0, yy) * .008
                if c < cost.get(m, 1e20):
                    cost[m], prev[m] = c, n
                    heapq.heappush(queue, (c + heuristic(m), c, m))
    else:
        raise ValueError("No collision-free monotone bridge route to target")

    # Merge collinear ramps. Retain every turn and grade change.
    keep = [0]
    for i in range(1, len(points) - 1):
        a, b = points[i] - points[i - 1], points[i + 1] - points[i]
        if np.linalg.norm(np.cross(a, b)) > 1e-7:
            keep.append(i)
    keep.append(len(points) - 1)
    return points[keep]


def bridge_geometry(points, width):
    tangent = np.diff(points[:, [0, 2]], axis=0)
    tangent /= np.linalg.norm(tangent, axis=1)[:, None]
    normal = np.stack((-tangent[:, 1], tangent[:, 0]), axis=1)
    offsets = np.zeros((len(points), 2))
    offsets[0], offsets[-1] = normal[0] * width / 2, normal[-1] * width / 2
    for i in range(1, len(points) - 1):
        n = normal[i - 1] + normal[i]
        n /= np.linalg.norm(n)
        offsets[i] = n * width / 2 / max(float(n @ normal[i]), .7)
    left, right = points.copy(), points.copy()
    left[:, [0, 2]] += offsets
    right[:, [0, 2]] -= offsets
    floor, rails, collision = [], [], []

    def quad(out, a, b, c, d):
        out.extend([[a.copy(), b.copy(), c.copy()], [a.copy(), c.copy(), d.copy()]])

    for i in range(len(points) - 1):
        a, b, c, d = left[i], left[i + 1], right[i + 1], right[i]
        quad(floor, a, b, c, d)
        for edge in (left, right):
            low_a, low_b = edge[i].copy(), edge[i + 1].copy()
            high_a, high_b = low_a.copy(), low_b.copy()
            high_a[1] += 1.25
            high_b[1] += 1.25
            quad(collision, low_a, low_b, high_b, high_a)
            bar_a, bar_b = low_a.copy(), low_b.copy()
            bar_a[1] += 1.10
            bar_b[1] += 1.10
            quad(rails, bar_a, bar_b, high_b, high_a)
            for fraction in np.linspace(0, 1, max(2, math.ceil(np.linalg.norm(low_b - low_a) / 4) + 1)):
                center = low_a * (1 - fraction) + low_b * fraction
                axis = (low_b - low_a) / np.linalg.norm(low_b - low_a) * .035
                p, q = center - axis, center + axis
                up = np.array([0., 1.25, 0.])
                quad(rails, p, q, q + up, p + up)
    collision.extend(floor)
    # Close the unused straight-ahead spur of the original hall bridge.
    # The new ramp leaves through the west side at z=-70.
    for a, b in [([6., 0., -74.8], [14., 0., -74.8]),
                 ([6., 0., -74.8], [6., 0., -71.4]),
                 ([14., 0., -74.8], [14., 0., -68.7])]:
        a, b = np.array(a), np.array(b)
        up = np.array([0., 1.25, 0.])
        quad(collision, a, b, b + up, a + up)
        quad(rails, a + up * .88, b + up * .88, b + up, a + up)
    return (np.array(collision, dtype='<f4'), np.array(floor, dtype='<f4'),
            np.array(rails, dtype='<f4'))


def guards(top, points, width):
    path = points[:, [0, 2]]
    starts, vectors = path[:-1], np.diff(path, axis=0)
    lengths_sq = (vectors * vectors).sum(axis=1)

    def corridor_distance(samples):
        delta = samples[:, None] - starts[None]
        fraction = np.clip((delta * vectors[None]).sum(axis=2) / lengths_sq, 0, 1)
        return np.linalg.norm(delta - fraction[:, :, None] * vectors[None], axis=2).min(axis=1)

    def bridge_height(sample):
        delta = sample[None] - starts
        fraction = np.clip((delta * vectors).sum(axis=1) / lengths_sq, 0, 1)
        nearest = np.argmin(np.linalg.norm(delta - fraction[:, None] * vectors, axis=1))
        return points[nearest, 1] * (1 - fraction[nearest]) + points[nearest + 1, 1] * fraction[nearest]
    supported = np.isfinite(top)
    # Do not erect tiny cages around narrow sampling pinholes. Test the void
    # at 0.25 m resolution against the real 0.30 m capsule radius; substantial
    # interior holes and all exterior missing regions keep their guards.
    missing, count = ndimage.label(~supported)
    fine_void = np.repeat(np.repeat(~supported, 2, 0), 2, 1)
    fine_labels = np.repeat(np.repeat(missing, 2, 0), 2, 1)
    radius = ndimage.maximum(ndimage.distance_transform_edt(fine_void) * .25,
                              labels=fine_labels, index=np.arange(count + 1))
    narrow = radius < .3
    exterior = np.unique(np.r_[missing[0], missing[-1], missing[:, 0], missing[:, -1]])
    narrow[exterior] = False
    narrow[0] = False
    supported |= narrow[missing]
    # Samples become cells centred at their world positions.
    faces, edges = [], []
    padded = np.pad(supported, 1)
    for dx, dz in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
        border = supported & ~padded[1 + dz:1 + dz + top.shape[0], 1 + dx:1 + dx + top.shape[1]]
        iz, ix = np.where(border)
        for z, x in zip(iz, ix):
            cx, cz = -288 + x * .5, -564 + z * .5
            y = float(top[z, x]) if np.isfinite(top[z, x]) else 0.
            a = np.array([cx + dx * .25 - dz * .25, cz + dz * .25 + dx * .25])
            b = np.array([cx + dx * .25 + dz * .25, cz + dz * .25 - dx * .25])
            a = np.clip(a, [-287.8, -558.4], [287.8, -75.])
            b = np.clip(b, [-287.8, -558.4], [287.8, -75.])
            if np.linalg.norm(a - b) < 1e-7:
                continue
            # Keep guards tight against bridge rails instead of fencing across its deck.
            midpoint = (a + b) * .5
            if corridor_distance(midpoint[None])[0] > width * .5 + .30:
                pieces = [(a, b)]
            else:
                samples = a[None] + np.linspace(0, 1, 11)[:, None] * (b - a)[None]
                pieces = [(samples[k], samples[k + 1]) for k in range(10)]
            for p, q in pieces:
                lo, hi = -40., min(100., y + 2.5)
                midpoint = (p + q) * .5
                ranges = [(lo, hi)]
                if corridor_distance(midpoint[None])[0] <= width * .5 + .04:
                    deck_y = bridge_height(midpoint)
                    ranges = [(lo, min(hi, deck_y - .16)), (max(lo, deck_y + 2.3), hi)]
                for bottom, upper in ranges:
                    if upper <= bottom:
                        continue
                    aa, bb = [p[0], bottom, p[1]], [q[0], bottom, q[1]]
                    cc, dd = [q[0], upper, q[1]], [p[0], upper, p[1]]
                    faces.extend([[aa, bb, cc], [aa, cc, dd]])
                edges.append({'a': p.tolist(), 'b': q.tolist(), 'surface_y': y, 'outward': [dx, dz]})
    return np.array(faces, dtype='<f4'), edges


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--top', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--target', nargs=3, type=float, default=[-62, 5.5, -148])
    parser.add_argument('--width', type=float, default=2.6)
    parser.add_argument('--support-mask', type=Path)
    parser.add_argument('--surface', type=Path)
    args = parser.parse_args()
    if args.out.exists():
        raise FileExistsError(args.out)
    top = np.fromfile(args.top, dtype='<f4').reshape(979, 1153)
    points = bridge_path(top, args.target, args.width)
    # Blend the elevated deck back into the measured street, so the return
    # trip does not face a vertical ledge at the original bridge endpoint.
    landing = points[-1] + np.array([0., 0., -4.])
    iz, ix = round((landing[2] + 564) * 2), round((landing[0] + 288) * 2)
    if not np.isfinite(top[iz, ix]):
        raise ValueError("Bridge landing must have measured native support")
    landing[1] = float(top[iz, ix]) + .06
    if abs(landing[1] - points[-1, 1]) > 1.:
        raise ValueError("Landing ramp exceeds the bridge grade limit")
    points = np.vstack((points, landing))
    bridge, floor, rails = bridge_geometry(points, args.width)
    boundary_top = top
    if args.support_mask or args.surface:
        if not (args.support_mask and args.surface):
            parser.error('--support-mask and --surface must be supplied together')
        support = np.fromfile(args.support_mask, dtype='u1').reshape(979, 1153).astype(bool)
        surface = np.fromfile(args.surface, dtype='<f4').reshape(979, 1153)
        boundary_top = np.where(support, surface, np.nan)
    boundary, edges = guards(boundary_top, points, args.width)
    args.out.mkdir(parents=True)
    for name, triangles in [('ScanBoundary', boundary), ('CampusBridgeExtension', bridge),
                            ('BridgeDeck', floor), ('BridgeRails', rails)]:
        triangles.tofile(args.out / (name + '.faces.f32'))
    report = {'grid_m': .5, 'grid_origin_xz': [-288, -564],
              'boundary_triangles': len(boundary), 'bridge_triangles': len(bridge),
              'bridge_width_m': args.width, 'bridge_points': points.tolist(),
              'bridge_length_m': float(np.linalg.norm(np.diff(points, axis=0), axis=1).sum()),
              'edges': edges,
              'support': 'measured ground cells; narrow interior sampling holes have no cages; missing columns are not filled' if args.support_mask else 'native ray hits; missing columns are not filled'}
    (args.out / 'access.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'edges'}, indent=2))


if __name__ == '__main__':
    main()
