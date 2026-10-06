#!/usr/bin/env python3
"""Render a seamlessly looping stage-backdrop clip from the painted backdrop, no Veo needed.

The painting drifts and breathes on a slow ellipse, cold teal mist boils over its lower half
and dust motes rise through it. Every motion is a sinusoid whose period divides the clip
length, so the last frame leads straight back into the first.

    python3 tools/render_backdrop_clip.py            # assets/video/raw/ossuary_nave.mp4
    tools/convert_backdrop.sh assets/video/raw/ossuary_nave.mp4

Needs numpy, Pillow and an ffmpeg with libx264 (`pip install numpy pillow`).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = REPO_ROOT / "assets" / "backdrops" / "ossuary_far.png"
DEFAULT_OUT = REPO_ROOT / "assets" / "video" / "raw" / "ossuary_nave.mp4"
MIST_COLOR = np.array([79.0, 127.0, 140.0], dtype=np.float32)  # BrawlTheme.MIST
MOTE_COLOR = np.array([205.0, 232.0, 236.0], dtype=np.float32)
MOTE_COUNT = 70
MOTE_RADIUS = 4


class Scene:
    """Precomputed, seed-determined parameters for one clip; render_frame(t) is pure."""

    def __init__(self, source: Image.Image, seconds: float, seed: int) -> None:
        self.width, self.height = source.size
        self.seconds = seconds
        self.source = source.convert("RGB")
        rng = np.random.RandomState(seed)
        # Two mist layers, each a sum of sinusoids with integer wave numbers over the frame
        # (periodic in x and y) and integer cycles per clip (periodic in t). Negative kx with
        # positive cycles reads as a slow leftward drift.
        self.mist_waves = []
        for _layer in range(2):
            waves = []
            for _ in range(7):
                kx = rng.randint(3, 9) * (-1 if rng.rand() < 0.75 else 1)
                ky = rng.randint(1, 4)
                cycles = rng.randint(1, 3)
                phase = rng.uniform(0.0, 2.0 * np.pi)
                amp = rng.uniform(0.5, 1.0) / (abs(kx) + ky)
                waves.append((kx, ky, cycles, phase, amp))
            self.mist_waves.append(waves)
        # Dust motes: periodic rise (an integer number of screen heights per clip) plus a sway.
        self.motes = []
        for _ in range(MOTE_COUNT):
            self.motes.append(
                (
                    rng.uniform(0.0, self.width),
                    rng.uniform(0.0, self.height),
                    rng.randint(1, 3),  # screen heights climbed per clip
                    rng.uniform(6.0, 22.0),  # sway amplitude px
                    rng.randint(1, 4),  # sway cycles per clip
                    rng.uniform(0.0, 2.0 * np.pi),
                    rng.uniform(0.35, 1.0),  # brightness
                )
            )
        ys, xs = np.mgrid[0 : self.height, 0 : self.width].astype(np.float32)
        self._u = xs * (2.0 * np.pi / self.width)
        self._v = ys * (2.0 * np.pi / self.height)
        # Mist lives in the lower half: 0 above 42% of the height, 1 from 78% down.
        band = np.clip((ys / self.height - 0.42) / 0.36, 0.0, 1.0)
        self._mist_band = (band * band * (3.0 - 2.0 * band))[..., None]
        r = np.arange(-MOTE_RADIUS, MOTE_RADIUS + 1, dtype=np.float32)
        self._mote_kernel = np.exp(-(r[:, None] ** 2 + r[None, :] ** 2) / (2.0 * 1.6**2))

    def painting(self, t: float) -> np.ndarray:
        """The source on a slow elliptical drift with a gentle zoom pulse (one cycle per clip)."""
        w = 2.0 * np.pi * t / self.seconds
        scale = 1.06 + 0.015 * np.sin(w)
        dx, dy = 14.0 * np.sin(w), 8.0 * np.cos(w)
        cx, cy = self.width / 2.0, self.height / 2.0
        # PIL's AFFINE takes the inverse map: output pixel -> source pixel.
        inv = 1.0 / scale
        matrix = (inv, 0.0, cx - (cx + dx) * inv, 0.0, inv, cy - (cy + dy) * inv)
        warped = self.source.transform(
            (self.width, self.height), Image.AFFINE, matrix, resample=Image.BICUBIC
        )
        return np.asarray(warped, dtype=np.float32)

    def mist(self, t: float, layer: int) -> np.ndarray:
        """Periodic noise field in 0..1 for one mist layer."""
        w = 2.0 * np.pi * t / self.seconds
        field = np.zeros((self.height, self.width), dtype=np.float32)
        total = 0.0
        for kx, ky, cycles, phase, amp in self.mist_waves[layer]:
            field += amp * np.sin(kx * self._u + ky * self._v + cycles * w + phase)
            total += amp
        return (field / total + 1.0) * 0.5

    def flicker(self, t: float) -> float:
        """Candle-light brightness wobble, +-4 %, built from 3 and 7 cycles per clip."""
        w = 2.0 * np.pi * t / self.seconds
        return 1.0 + 0.04 * (0.6 * np.sin(3.0 * w) + 0.4 * np.sin(7.0 * w + 1.0))

    def render_frame(self, t: float) -> np.ndarray:
        """One RGB frame (uint8, height x width x 3) at time t seconds."""
        frame = self.painting(t) * self.flicker(t)
        near = self.mist(t, 0)
        far = self.mist(t, 1)
        density = np.clip(near * 0.65 + far * 0.35, 0.0, 1.0) ** 1.6
        alpha = self._mist_band * density[..., None] * 0.42
        frame = frame * (1.0 - alpha) + MIST_COLOR * alpha
        self._stamp_motes(frame, t)
        return np.clip(frame, 0.0, 255.0).astype(np.uint8)

    def _stamp_motes(self, frame: np.ndarray, t: float) -> None:
        phase_t = t / self.seconds
        k = MOTE_RADIUS
        for x0, y0, climbs, sway, sway_cycles, sway_phase, brightness in self.motes:
            x = x0 + sway * np.sin(2.0 * np.pi * sway_cycles * phase_t + sway_phase)
            y = (y0 - climbs * self.height * phase_t) % self.height
            # Twinkle with the climb so a mote fades out before wrapping to the bottom.
            glow = brightness * (0.5 + 0.5 * np.sin(2.0 * np.pi * (y / self.height) + 1.5))
            xi, yi = int(round(x)) % self.width, int(round(y))
            y0_, y1_ = max(0, yi - k), min(self.height, yi + k + 1)
            x0_, x1_ = max(0, xi - k), min(self.width, xi + k + 1)
            if y0_ >= y1_ or x0_ >= x1_:
                continue
            kern = self._mote_kernel[y0_ - yi + k : y1_ - yi + k, x0_ - xi + k : x1_ - xi + k]
            frame[y0_:y1_, x0_:x1_] += (kern * glow)[..., None] * MOTE_COLOR


def frame_times(seconds: float, fps: int) -> list[float]:
    """Frame timestamps for one loop; the frame after the last one is t == seconds == frame 0."""
    count = int(round(seconds * fps))
    return [i / fps for i in range(count)]


def encode(scene: Scene, out: Path, fps: int, ffmpeg: str) -> int:
    out.parent.mkdir(parents=True, exist_ok=True)
    command = [
        ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{scene.width}x{scene.height}",
        "-r", str(fps), "-i", "-",
        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
        str(out),
    ]  # fmt: skip
    times = frame_times(scene.seconds, fps)
    with subprocess.Popen(command, stdin=subprocess.PIPE) as proc:
        assert proc.stdin is not None
        for index, t in enumerate(times):
            proc.stdin.write(scene.render_frame(t).tobytes())
            if index % fps == 0:
                print(f"  {index}/{len(times)} frames", file=sys.stderr)
        proc.stdin.close()
        proc.wait()
    if proc.returncode != 0:
        raise SystemExit(f"ffmpeg exited {proc.returncode}")
    return len(times)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="painted backdrop PNG")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="mp4 to write")
    parser.add_argument("--seconds", type=float, default=8.0, help="loop length")
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    scene = Scene(Image.open(args.source), args.seconds, args.seed)
    print(f"rendering {args.seconds:g}s at {args.fps} fps ({scene.width}x{scene.height}) -> {args.out}")
    frames = encode(scene, args.out, args.fps, args.ffmpeg)
    print(f"wrote {args.out} ({frames} frames, {args.out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
