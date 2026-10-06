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


def _dark_scene() -> rbc.Scene:
    """A flat dark painting, so a mote's light is the only difference between two frames."""
    pixels = np.full((36, 64, 3), 20, dtype=np.uint8)
    return rbc.Scene(Image.fromarray(pixels), 2.0, 3)


def _mote_light(scene: rbc.Scene, x: float, y: float) -> np.ndarray:
    """Per-pixel brightness a single full-brightness, non-swaying mote at (x, y) adds at t = 0."""
    scene.motes = []
    base = scene.render_frame(0.0).astype(np.int16)
    scene.motes = [(x, y, 1, 0.0, 1, 0.0, 1.0)]
    return np.abs(scene.render_frame(0.0).astype(np.int16) - base).max(axis=2)


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

    def test_motes_fade_out_at_the_wrap_edges(self) -> None:
        """A mote is dark where y wraps (top and bottom rows) and bright mid-screen."""
        scene = _dark_scene()
        self.assertEqual(int(_mote_light(scene, 32.0, 0.0).max()), 0)
        self.assertLessEqual(int(_mote_light(scene, 32.0, 35.0).max()), 2)
        self.assertGreaterEqual(int(_mote_light(scene, 32.0, 18.0).max()), 100)

    def test_mote_past_the_left_edge_does_not_wrap_to_the_right(self) -> None:
        """A mote swaying past x = 0 is clipped there, never stamped at the right edge."""
        lit_columns = np.flatnonzero(_mote_light(_dark_scene(), -2.0, 18.0).max(axis=0) > 0)
        self.assertGreater(len(lit_columns), 0)
        self.assertLessEqual(int(lit_columns.max()), rbc.MOTE_RADIUS)

    def test_frame_times_cover_one_loop(self) -> None:
        times = rbc.frame_times(8.0, 30)
        self.assertEqual(len(times), 240)
        self.assertEqual(times[0], 0.0)
        self.assertAlmostEqual(times[-1] + 1.0 / 30.0, 8.0)


if __name__ == "__main__":
    unittest.main()
