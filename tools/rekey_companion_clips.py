"""Rebuild the third Arona/Plana clips from their original local green-screen videos.

Uses a colour-difference matte and background decontamination. Unlike a large
chroma-distance threshold, pale ribbons, hair and umbrella edges remain visible.
Frame geometry is the union of the whole animation, never a per-frame crop.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import tempfile

import numpy as np
from PIL import Image

CLIPS = {
    "arona": ("绿幕素材分享（阿洛娜木偶）_视频.mp4", 15),
    "plana": ("普拉娜木偶绿幕素材_视频.mp4", 15),
}


def key_frame(rgb: np.ndarray, kind: str) -> np.ndarray:
    colour = rgb.astype(np.float32)
    background = np.median(colour[120:400, 40:90].reshape(-1, 3), axis=0)
    red, green, blue = colour.transpose(2, 0, 1)
    difference = green - np.maximum(red, blue)
    backing_difference = background[1] - max(background[0], background[2])
    alpha = 1.0 - np.clip((difference - 4.0) / (backing_difference - 8.0), 0.0, 1.0)
    chroma_distance = np.hypot(
        red / np.maximum(green, 1) - background[0] / background[1],
        blue / np.maximum(green, 1) - background[2] / background[1],
    )
    alpha[chroma_distance < 0.045] = 0
    # Source black pillarboxes are not part of the silhouette.
    alpha[:, :32] = 0
    alpha[:, -32:] = 0
    if kind == "plana":
        # Match the existing character-only asset: source credits remain in credits.gd.
        # Source lettering is green-tinted. Key those pixels individually: the
        # moving white bow crosses this area and must never be rectangle-masked.
        corner = alpha[:110, :500]
        corner[difference[:110, :500] > 10.0] = 0
        alpha[1180:] = 0
    corrected = (colour - (1.0 - alpha[..., None]) * background) / np.maximum(alpha[..., None], 0.02)
    corrected = np.clip(corrected, 0, 255)
    spill = (difference > 4.0) & (alpha < 0.999)
    corrected[..., 1][spill] = np.minimum(corrected[..., 1], np.maximum(corrected[..., 0], corrected[..., 2]))[spill]
    corrected[alpha < 0.015] = 0
    return np.dstack((corrected.astype(np.uint8), np.rint(alpha * 255).astype(np.uint8)))


def rebuild(kind: str, source_dir: Path, root: Path, ffmpeg: str, sample: bool) -> dict:
    filename, fps = CLIPS[kind]
    source = source_dir / filename
    if not source.is_file():
        raise FileNotFoundError(source)
    destination = root / "assets" / f"{kind}_frames_c"
    destination.mkdir(parents=True, exist_ok=True)
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    with tempfile.TemporaryDirectory(prefix=f"{kind}_rekey_") as staging:
        temp = Path(staging)
        command = [ffmpeg, "-v", "error", "-i", str(source), "-vf", f"fps={fps}"]
        if sample:
            command += ["-frames:v", "1"]
        subprocess.run(command + ["-threads", "1", str(temp / "raw_%04d.png")], check=True, creationflags=flags)
        union = None
        frames = sorted(temp.glob("raw_*.png"))
        for index, frame in enumerate(frames, 1):
            rgba = key_frame(np.array(Image.open(frame).convert("RGB")), kind)
            mask = rgba[..., 3] > 16
            ys, xs = np.nonzero(mask)
            if not len(xs):
                raise ValueError(f"empty silhouette: {frame}")
            box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
            union = box if union is None else tuple(
                min(union[j], box[j]) if j < 2 else max(union[j], box[j]) for j in range(4))
            Image.fromarray(rgba).save(temp / f"key_{index:04d}.png", compress_level=1)
        union = (max(0, union[0] - 4), max(0, union[1] - 4), min(1080, union[2] + 4), min(1440 if kind == "arona" else 1350, union[3] + 4))
        output = root / "_tools" / "_tmp" / f"{kind}_c_rekey_sample.png" if sample else None
        for index in range(1, len(frames) + 1):
            target = output if sample else destination / f"f_{index:04d}.png"
            Image.open(temp / f"key_{index:04d}.png").crop(union).save(target, compress_level=6)
        if not sample:
            # Explicitly limit stale-file cleanup to this clip's generated numbered frames.
            for path in destination.glob("f_*.png"):
                if int(path.stem[2:]) > len(frames):
                    path.unlink()
    return {"clip": kind, "fps": fps, "frames": len(frames), "crop": union, "destination": str(output or destination)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=Path.home() / "Downloads")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--ffmpeg", default="D:/SOFTWARE/ffmpeg/bin/ffmpeg.exe")
    parser.add_argument("--sample", action="store_true")
    parser.add_argument("--clip", choices=tuple(CLIPS), action="append")
    args = parser.parse_args()
    for kind in args.clip or CLIPS:
        print(json.dumps(rebuild(kind, args.source_dir, args.project, args.ffmpeg, args.sample), ensure_ascii=True), flush=True)


if __name__ == "__main__":
    main()
