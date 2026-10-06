"""Unit tests for tools/render_backdrop_clip.py (small frames, no ffmpeg)."""

from __future__ import annotations

import unittest

import numpy as np
from PIL import Image

from tools import render_backdrop_clip as rbc


def _scene(seconds: float = 2.0, seed: int = 3) -> rbc.Scene:
    rng = np.random.RandomState(1)
    pixels = rng.randint(0, 256, size=(36, 64, 3), dtype=np.uint8)
    return rbc.Scene(Image.fromarray(pixels), seconds, seed)


class RenderBackdropClipTests(unittest.TestCase):
    def test_frame_shape_and_dtype(self) -> None:
        frame = _scene().render_frame(0.7)
        self.assertEqual(frame.shape, (36, 64, 3))
        self.assertEqual(frame.dtype, np.uint8)

    def test_loop_is_seamless(self) -> None:
        """Frame at t == seconds equals frame 0, so the last frame leads back into the first."""
        scene = _scene()
        first = scene.render_frame(0.0).astype(np.int16)
        wrapped = scene.render_frame(scene.seconds).astype(np.int16)
        self.assertLessEqual(int(np.abs(first - wrapped).max()), 1)

    def test_mid_clip_frame_differs_from_first(self) -> None:
        scene = _scene()
        first = scene.render_frame(0.0).astype(np.int16)
        middle = scene.render_frame(scene.seconds / 2.0).astype(np.int16)
        self.assertGreater(int(np.abs(first - middle).max()), 8)

    def test_same_seed_renders_identical_frames(self) -> None:
        a = _scene(seed=11).render_frame(0.4)
        b = _scene(seed=11).render_frame(0.4)
        self.assertTrue(np.array_equal(a, b))

    def test_mist_only_touches_lower_band(self) -> None:
        """Rows above 42 % of the height carry no mist (the painting is only flickered)."""
        scene = _scene()
        band = scene._mist_band[:, 0, 0]
        self.assertTrue(np.all(band[: int(36 * 0.42)] == 0.0))
        self.assertTrue(np.all(band[int(36 * 0.78) + 1 :] == 1.0))

    def test_frame_times_cover_one_loop(self) -> None:
        times = rbc.frame_times(8.0, 30)
        self.assertEqual(len(times), 240)
        self.assertEqual(times[0], 0.0)
        self.assertAlmostEqual(times[-1] + 1.0 / 30.0, 8.0)


if __name__ == "__main__":
    unittest.main()
