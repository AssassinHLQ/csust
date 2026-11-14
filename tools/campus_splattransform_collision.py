"""Prepare native SplatTransform collision input in the campus world frame.

The exported 3DGS PLY uses the original SOG coordinates. Apply frame.json
exactly once to positions, rotations and scales. The CLI's ``--rotate 0,0,180``
cancels its implicit PLY orientation, so the collision GLB remains Godot Y-up.
Generated input, logs and candidates belong under _tools/_tmp, never in Git.
"""

import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

ROOT = Path(__file__).resolve().parents[1]


def read_ply(path):
    props = []
    count = None
    with path.open("rb") as stream:
        if stream.readline().strip() != b"ply":
            raise ValueError("Not a PLY file")
        while True:
            line = stream.readline().decode("ascii").strip()
            if line.startswith("format ") and line != "format binary_little_endian 1.0":
                raise ValueError("Expected binary little-endian PLY")
            if line.startswith("element vertex "):
                count = int(line.split()[-1])
            elif line.startswith("property "):
                _, typ, name = line.split()
                if typ != "float":
                    raise ValueError("Expected float properties")
                props.append(name)
            elif line == "end_header":
                break
            elif not line:
                raise ValueError("Truncated PLY header")
        offset = stream.tell()
    if count is None or path.stat().st_size != offset + count * len(props) * 4:
        raise ValueError("Unexpected PLY data size")
    data = np.memmap(path, dtype="<f4", mode="r", offset=offset, shape=(count, len(props)))
    return data, {name: i for i, name in enumerate(props)}


def prepare(args):
    source = args.source.resolve()
    out = args.out.resolve()
    if out.exists():
        raise FileExistsError(out)
    frame_path = ROOT / "splatdata/campus_sog/frame.json"
    frame_bytes = frame_path.read_bytes()
    frame = json.loads(frame_bytes.decode("utf-8-sig"))
    basis = np.array(frame["axes"], dtype=np.float64).T
    origin = np.array(frame["origin"], dtype=np.float64)
    scale = np.linalg.norm(basis, axis=0).mean()
    rotation = Rotation.from_matrix(basis / scale)
    if not np.allclose(basis.T @ basis, np.eye(3) * scale**2, atol=.003):
        raise ValueError("Campus frame is no longer a uniform similarity transform")
    data, fields = read_ply(source)
    xyz = data[:, [fields[x] for x in ("x", "y", "z")]]
    keep = np.all((xyz >= frame["box_min"]) & (xyz <= frame["box_max"]), axis=1)
    ids = np.flatnonzero(keep)
    reference = np.memmap(ROOT / "campus_ggs.bin", dtype="<f4", mode="r").reshape(-1, 60)
    if len(ids) != len(reference):
        raise ValueError("Source PLY and campus world data have different retained point counts")
    sample = np.arange(0, len(ids), max(1, len(ids) // 20000))
    src_sample = data[ids[sample]]
    world_sample = xyz[ids[sample]] @ basis.T + origin
    position_error = float(np.max(np.abs(world_sample - reference[sample, :3])))
    quaternion_fields = [fields[n] for n in ("rot_1", "rot_2", "rot_3", "rot_0")]
    scale_fields = [fields[n] for n in ("scale_0", "scale_1", "scale_2")]
    wr = rotation * Rotation.from_quat(src_sample[:, quaternion_fields])
    ws = np.exp(src_sample[:, scale_fields]) * scale
    rm = wr.as_matrix()
    cov = np.einsum("nij,nj,nkj->nik", rm, ws * ws, rm)
    covariance_error = float(np.max(np.abs(
        cov[:, (0, 0, 0, 1, 1, 2), (0, 1, 2, 1, 2, 2)] - reference[sample, 4:10]
    )))
    if position_error > .001 or covariance_error > .001:
        raise ValueError(f"Frame verification failed: position {position_error}, covariance {covariance_error}")
    del reference
    props = ["x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
             "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]
    out.parent.mkdir(parents=True, exist_ok=True)
    header = "ply\nformat binary_little_endian 1.0\nelement vertex {count:010d}\n"
    header += "".join(f"property float {p}\n" for p in props) + "end_header\n"
    count = 0
    bounds_min = np.full(3, np.inf)
    bounds_max = np.full(3, -np.inf)
    lo = np.array(args.bounds[:3]) if args.bounds else None
    hi = np.array(args.bounds[3:]) if args.bounds else None
    with out.open("wb") as stream:
        stream.write(header.format(count=0).encode("ascii"))
        for begin in range(0, len(ids), 100000):
            chunk = data[ids[begin:begin + 100000]]
            positions = chunk[:, :3] @ basis.T + origin
            scales = np.exp(chunk[:, scale_fields]) * scale
            radius = 3 * scales.max(axis=1)
            selected = np.isfinite(positions).all(axis=1) & np.isfinite(scales).all(axis=1)
            if lo is not None:
                # Retain every Gaussian whose 3-sigma support intersects the bake volume.
                selected &= ((positions + radius[:, None] >= lo) &
                             (positions - radius[:, None] <= hi)).all(axis=1)
            if args.max_scale:
                selected &= scales.max(axis=1) <= args.max_scale
            positions = positions[selected]
            chunk = chunk[selected]
            if not len(chunk):
                continue
            result = np.empty((len(chunk), len(props)), dtype="<f4")
            result[:, :3] = positions
            result[:, 3:6] = chunk[:, [fields[n] for n in props[3:6]]]
            result[:, 6] = chunk[:, fields["opacity"]]
            result[:, 7:10] = chunk[:, scale_fields] + np.log(scale)
            q = (rotation * Rotation.from_quat(chunk[:, quaternion_fields])).as_quat()
            result[:, 10:14] = q[:, [3, 0, 1, 2]]
            stream.write(result.tobytes())
            count += len(chunk)
            bounds_min = np.minimum(bounds_min, positions.min(axis=0))
            bounds_max = np.maximum(bounds_max, positions.max(axis=0))
        stream.seek(0)
        stream.write(header.format(count=count).encode("ascii"))
    if not count:
        raise ValueError("No selected points")
    manifest = {
        "source": str(source), "source_points": len(data), "retained_source_points": len(ids),
        "points": count, "frame": str(frame_path),
        "frame_sha256": hashlib.sha256(frame_bytes).hexdigest(),
        "position_max_error_m": position_error, "covariance_max_error": covariance_error,
        "verified_samples": len(sample), "world_bounds": [bounds_min.tolist(), bounds_max.tolist()],
        "selection_bounds": args.bounds, "max_scale_m": args.max_scale,
        "cli_orientation": "--rotate 0,0,180 cancels Transform.PLY; GLB is world Y-up",
    }
    out.with_suffix(".json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2), flush=True)


def split(args):
    data, fields = read_ply(args.input)
    args.out.mkdir(parents=True, exist_ok=True)
    if any(args.out.iterdir()):
        raise FileExistsError("Tile staging directory must be empty")
    positions = data[:, :3]
    radius = 3 * np.exp(data[:, [fields[n] for n in ("scale_0", "scale_1", "scale_2")]]).max(axis=1)
    manifest = {"input": str(args.input.resolve()), "voxel_m": .25, "halo_m": args.halo,
                "tile_m": 96, "origin_xz": [-288, -564], "tiles": []}
    for iz in range(6):
        for ix in range(6):
            lo = np.array([-288 + ix * 96, -564 + iz * 96])
            hi = lo + 96
            select = ((positions[:, [0, 2]] + radius[:, None] >= lo - args.halo) &
                      (positions[:, [0, 2]] - radius[:, None] <= hi + args.halo)).all(axis=1)
            count = int(select.sum())
            if count < 100:
                continue
            path = args.out / f"Tile_{ix}_{iz}.ply"
            props = [name for name, i in sorted(fields.items(), key=lambda pair: pair[1])]
            header = f"ply\nformat binary_little_endian 1.0\nelement vertex {count}\n"
            header += "".join(f"property float {p}\n" for p in props) + "end_header\n"
            with path.open("wb") as stream:
                stream.write(header.encode("ascii"))
                stream.write(data[select].tobytes())
            manifest["tiles"].append({"name": path.stem, "points": count,
                                      "core_min_xz": lo.tolist(), "core_max_xz": hi.tolist()})
            print(path.stem, count, flush=True)
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def clip_triangles(triangles, axis, boundary, greater):
    """Clip triangles against a plane without adding a vertical end cap."""
    values = triangles[:, :, axis]
    within = values >= boundary if greater else values <= boundary
    result = [triangles[within.all(axis=1)]]
    crossing = triangles[within.any(axis=1) & ~within.all(axis=1)]
    for triangle in crossing:
        polygon = []
        previous = triangle[-1]
        previous_in = previous[axis] >= boundary if greater else previous[axis] <= boundary
        for current in triangle:
            current_in = current[axis] >= boundary if greater else current[axis] <= boundary
            if previous_in != current_in:
                ratio = (boundary - previous[axis]) / (current[axis] - previous[axis])
                point = previous + ratio * (current - previous)
                point[axis] = boundary
                polygon.append(point)
            if current_in:
                polygon.append(current)
            previous, previous_in = current, current_in
        for i in range(1, len(polygon) - 1):
            result.append(np.array([[polygon[0], polygon[i], polygon[i + 1]]]))
    return np.concatenate(result)


def bake(args):
    """Run bounded, sequential CLI jobs; never create a visible console."""
    import trimesh
    tiles = json.loads((args.input / "manifest.json").read_text(encoding="utf-8"))
    args.out.mkdir(parents=True, exist_ok=True)
    cli = args.runtime / "node_modules/@playcanvas/splat-transform/bin/cli.mjs"
    simplifier = ROOT / "tools/simplify_campus_collision.mjs"
    reports = []
    for tile in tiles["tiles"]:
        name = tile["name"]
        prefix = args.out / name
        marker = prefix.with_suffix(".complete.json")
        if marker.exists():
            reports.append(json.loads(marker.read_text(encoding="utf-8")))
            continue
        started = time.monotonic()
        command = ["node", "--max-old-space-size=4096", str(cli), str(args.input / (name + ".ply")),
                   "--rotate", "0,0,180", "--voxel-size", str(args.voxel), "--voxel-opacity", str(args.opacity),
                   "--collision-mesh", "smooth", "--gpu", "0", "--no-tty", "--overwrite",
                   str(prefix.with_suffix(".voxel.json"))]
        with prefix.with_suffix(".bake.log").open("w", encoding="utf-8") as log:
            subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT,
                           creationflags=subprocess.CREATE_NO_WINDOW)
        mesh = trimesh.load(prefix.with_suffix(".collision.glb"), force="mesh", process=False)
        raw_count = len(mesh.faces)
        original = mesh.vertices.copy()
        trimesh.smoothing.filter_taubin(mesh, lamb=.5, nu=.53, iterations=16)
        delta = mesh.vertices - original
        distance = np.linalg.norm(delta, axis=1)
        mesh.vertices = original + delta * np.minimum(1, args.voxel / np.maximum(distance, 1e-12))[:, None]
        mesh.vertices.astype("<f4").tofile(prefix.with_suffix(".vertices.f32"))
        mesh.faces.astype("<u4").tofile(prefix.with_suffix(".indices.u32"))
        del mesh, original, delta, distance
        with prefix.with_suffix(".simplify.log").open("w", encoding="utf-8") as log:
            subprocess.run(["node", str(simplifier), str(args.runtime), str(prefix), str(args.error)],
                           check=True, stdout=log, stderr=subprocess.STDOUT,
                           creationflags=subprocess.CREATE_NO_WINDOW)
        triangles = np.fromfile(prefix.with_suffix(".faces.f32"), dtype="<f4").reshape(-1, 3, 3)
        for axis, lo, hi in zip((0, 2), tile["core_min_xz"], tile["core_max_xz"]):
            triangles = clip_triangles(triangles, axis, lo, True)
            triangles = clip_triangles(triangles, axis, hi, False)
        area = np.linalg.norm(np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0]), axis=1)
        triangles = triangles[area > 1e-8]
        triangles.astype("<f4").tofile(prefix.with_suffix(".faces.f32"))
        report = dict(tile, raw_triangles=raw_count, triangles=len(triangles),
                      seconds=time.monotonic() - started, voxel_m=args.voxel,
                      opacity=args.opacity, relaxation_max_m=args.voxel, simplification_error_m=args.error)
        marker.write_text(json.dumps(report, indent=2), encoding="utf-8")
        reports.append(report)
        print(json.dumps(report), flush=True)
        del triangles, area
    manifest = dict(tiles, tiles=reports, tool="@playcanvas/splat-transform 3.11.2",
                    voxel_m=args.voxel, opacity=args.opacity,
                    triangles=sum(t["triangles"] for t in reports))
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def finish(args):
    """Clip before simplification so LockBorder preserves every core edge."""
    import trimesh
    manifest_path = args.source / "manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    else:
        manifest = {"partial": True, "tiles": [json.loads(p.read_text(encoding="utf-8"))
                    for p in sorted(args.source.glob("*.complete.json"))]}
    args.out.mkdir(parents=True, exist_ok=True)
    reports = []
    for tile in manifest["tiles"]:
        prefix = args.out / tile["name"]
        core_min = np.maximum(tile["core_min_xz"], [-287.8, -558.4]).tolist()
        core_max = np.minimum(tile["core_max_xz"], [287.8, -75.0]).tolist()
        needs_clip = core_min != tile["core_min_xz"] or core_max != tile["core_max_xz"]
        if prefix.with_suffix(".complete.json").exists():
            cached = json.loads(prefix.with_suffix(".complete.json").read_text(encoding="utf-8"))
            if (cached.get("relaxation_iterations", 16) != args.iterations or
                    cached.get("relaxation_max_m", .25) != args.relaxation or
                    cached.get("simplification_error_m") != args.error):
                raise ValueError(f"Cached settings differ for {prefix}; choose a fresh output directory")
            if not needs_clip or cached.get("footprint_clipped", False):
                reports.append(cached)
                continue
        started = time.monotonic()
        mesh = trimesh.load((args.source / tile["name"]).with_suffix(".collision.glb"), force="mesh", process=False)
        original = mesh.vertices.copy()
        trimesh.smoothing.filter_taubin(mesh, lamb=.5, nu=.53, iterations=args.iterations)
        delta = mesh.vertices - original
        distance = np.linalg.norm(delta, axis=1)
        mesh.vertices = original + delta * np.minimum(1, args.relaxation / np.maximum(distance, 1e-12))[:, None]
        triangles = mesh.triangles
        del mesh, original, delta, distance
        for axis, lo, hi in zip((0, 2), core_min, core_max):
            triangles = clip_triangles(triangles, axis, lo, True)
            triangles = clip_triangles(triangles, axis, hi, False)
        mesh = trimesh.Trimesh(vertices=triangles.reshape(-1, 3),
                               faces=np.arange(triangles.size // 3).reshape(-1, 3), process=True)
        mesh.update_faces(mesh.nondegenerate_faces())
        mesh.remove_unreferenced_vertices()
        mesh.vertices.astype("<f4").tofile(prefix.with_suffix(".vertices.f32"))
        mesh.faces.astype("<u4").tofile(prefix.with_suffix(".indices.u32"))
        del mesh, triangles
        with prefix.with_suffix(".simplify.log").open("w", encoding="utf-8") as log:
            subprocess.run(["node", str(ROOT / "tools/simplify_campus_collision.mjs"), str(args.runtime),
                            str(prefix), str(args.error)], check=True, stdout=log, stderr=subprocess.STDOUT,
                           creationflags=subprocess.CREATE_NO_WINDOW)
        simplification = json.loads(prefix.with_suffix(".simplification.json").read_text(encoding="utf-8"))
        report = dict(tile, triangles=simplification["simplified_triangles"],
                      seconds=time.monotonic() - started, simplification_error_m=args.error,
                      relaxation_max_m=args.relaxation, relaxation_iterations=args.iterations,
                      boundary="core clipped before LockBorder simplification; no closing caps",
                      footprint_clipped=True, core_min_xz=core_min, core_max_xz=core_max)
        prefix.with_suffix(".complete.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        reports.append(report)
        print(json.dumps(report), flush=True)
    manifest.update(tiles=reports, triangles=sum(t["triangles"] for t in reports))
    prepared_manifest = Path(manifest["input"]).with_suffix(".json")
    if prepared_manifest.exists():
        preparation = json.loads(prepared_manifest.read_text(encoding="utf-8"))
        manifest["coordinate_verification"] = {k: preparation[k] for k in (
            "frame_sha256", "position_max_error_m", "covariance_max_error", "verified_samples", "cli_orientation")}
    manifest["coordinate_space"] = "Godot campus world; identity transform on imported nodes"
    manifest["postprocess"] = {"taubin_lambda": .5, "taubin_nu": .53,
                               "iterations": args.iterations, "max_displacement_m": args.relaxation,
                               "simplification_error_m": args.error}
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def ground(args):
    """Smooth thin native ground shells without creating support in empty areas."""
    import trimesh
    from scipy import ndimage
    source = args.source
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("partial"):
        raise ValueError("A complete native bake is required")
    if args.out.exists():
        raise FileExistsError(args.out)
    args.out.mkdir(parents=True)
    raw = np.fromfile(args.heightfield, dtype="<f4").reshape(979, 1153)
    valid = np.isfinite(raw)
    if not valid.any():
        raise ValueError("Heightfield has no supported samples")
    distance, nearest = ndimage.distance_transform_edt(~valid, return_indices=True)
    filled = raw[tuple(nearest)]
    median = ndimage.median_filter(filled, size=5, mode="nearest")
    target = ndimage.gaussian_filter(median, sigma=2., mode="nearest")
    target = filled + np.clip(target - filled, -.8, .8)
    reports = []
    for tile in manifest["tiles"]:
        prefix = args.out / tile["name"]
        triangles = np.fromfile(source / (tile["name"] + ".faces.f32"), dtype="<f4").reshape(-1, 3, 3)
        mesh = trimesh.Trimesh(vertices=triangles.reshape(-1, 3),
                               faces=np.arange(triangles.size // 3).reshape(-1, 3), process=True)
        xyz = mesh.vertices
        coords = np.stack(((xyz[:, 2] + 564) / .5, (xyz[:, 0] + 288) / .5))
        smooth_y = ndimage.map_coordinates(target, coords, order=1, mode="nearest")
        native_y = ndimage.map_coordinates(filled, coords, order=1, mode="nearest")
        supported = ndimage.map_coordinates(distance, coords, order=1, mode="constant", cval=100) < 1.5
        weight = np.clip((2. - np.abs(native_y - xyz[:, 1])) / .7, 0, 1) * supported
        mesh.vertices[:, 1] += (smooth_y - xyz[:, 1]) * weight
        mesh.update_faces(mesh.nondegenerate_faces())
        mesh.remove_unreferenced_vertices()
        mesh.vertices.astype("<f4").tofile(prefix.with_suffix(".vertices.f32"))
        mesh.faces.astype("<u4").tofile(prefix.with_suffix(".indices.u32"))
        with prefix.with_suffix(".simplify.log").open("w", encoding="utf-8") as log:
            subprocess.run(["node", str(ROOT / "tools/simplify_campus_collision.mjs"), str(args.runtime),
                            str(prefix), str(args.error)], check=True, stdout=log, stderr=subprocess.STDOUT,
                           creationflags=subprocess.CREATE_NO_WINDOW)
        simplified = json.loads(prefix.with_suffix(".simplification.json").read_text())
        report = dict(tile, triangles=simplified["simplified_triangles"])
        reports.append(report)
        print(json.dumps(report), flush=True)
    manifest.update(tiles=reports, triangles=sum(t["triangles"] for t in reports),
                    ground_filter={"grid_m": .5, "sample_top_m": 8, "sample_bottom_m": -20,
                                   "median_cells": 5, "gaussian_sigma_cells": 2.,
                                   "height_correction_cap_m": .8, "native_shell_band_m": 1.3,
                                   "native_shell_fade_m": .7, "simplification_error_m": args.error,
                                   "geometry": "existing native vertices only; no added floor or skirts; world X/Z retained"})
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("prepare")
    command.add_argument("--source", type=Path, default=ROOT.parent / "_arisu_captures/campus_3dgs.ply")
    command.add_argument("--out", type=Path, required=True)
    command.add_argument("--bounds", nargs=6, type=float)
    command.add_argument("--max-scale", type=float, default=0)
    command.set_defaults(run=prepare)
    command = commands.add_parser("split")
    command.add_argument("--input", type=Path, required=True)
    command.add_argument("--out", type=Path, required=True)
    command.add_argument("--halo", type=float, default=8)
    command.set_defaults(run=split)
    command = commands.add_parser("bake")
    command.add_argument("--input", type=Path, required=True)
    command.add_argument("--out", type=Path, required=True)
    command.add_argument("--runtime", type=Path, required=True)
    command.add_argument("--voxel", type=float, default=.25)
    command.add_argument("--opacity", type=float, default=.3)
    command.add_argument("--error", type=float, default=.125)
    command.set_defaults(run=bake)
    command = commands.add_parser("finish")
    command.add_argument("--source", type=Path, required=True)
    command.add_argument("--out", type=Path, required=True)
    command.add_argument("--runtime", type=Path, required=True)
    command.add_argument("--error", type=float, default=.125)
    command.add_argument("--iterations", type=int, default=16)
    command.add_argument("--relaxation", type=float, default=.25)
    command.set_defaults(run=finish)
    command = commands.add_parser("ground")
    command.add_argument("--source", type=Path, required=True)
    command.add_argument("--heightfield", type=Path, required=True)
    command.add_argument("--out", type=Path, required=True)
    command.add_argument("--runtime", type=Path, required=True)
    command.add_argument("--error", type=float, default=.1)
    command.set_defaults(run=ground)
    args = parser.parse_args()
    if args.command == "finish" and not (1 <= args.iterations <= 128 and 0 < args.relaxation <= 1):
        parser.error("finish requires 1..128 iterations and a relaxation cap in (0, 1] metres")
    args.run(args)


if __name__ == "__main__":
    main()
