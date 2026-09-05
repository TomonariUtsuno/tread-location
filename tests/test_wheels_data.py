"""Regression tests for the canonical tread wheel catalogue tools."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from wheels_data import CatalogError, load_catalog, render_data_js  # noqa: E402


IMAGE_SPEC = {
    "format": "png",
    "width": 533,
    "height": 800,
    "colorModel": "RGB",
    "bitDepth": 8,
    "alpha": False,
}


def write_catalog(directory: Path, wheels: list[dict[str, object]]) -> Path:
    path = directory / "wheels.json"
    path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "imageSpecification": IMAGE_SPEC,
                "wheels": wheels,
            }
        ),
        encoding="utf-8",
    )
    return path


class WheelsDataTests(unittest.TestCase):
    def test_generated_browser_data_matches_the_committed_file(self) -> None:
        catalog = load_catalog(ROOT / "wheels.json")
        self.assertEqual(len(catalog.wheels), 36)
        self.assertEqual(render_data_js(catalog), (ROOT / "data.js").read_text(encoding="utf-8"))

    def test_duplicate_number_is_rejected(self) -> None:
        wheels = [
            {"number": 1, "lat": 35, "lng": 135, "image": "wheels/w001.png"},
            {"number": 1, "lat": 36, "lng": 136, "image": "wheels/w001.png"},
        ]
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(CatalogError, "duplicate wheel number"):
                load_catalog(write_catalog(Path(temporary), wheels))

    def test_duplicate_image_path_is_rejected(self) -> None:
        wheels = [
            {"number": 1, "lat": 35, "lng": 135, "image": "wheels/w001.png"},
            {"number": 2, "lat": 36, "lng": 136, "image": "wheels/w001.png"},
        ]
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(CatalogError, "duplicate image path"):
                load_catalog(write_catalog(Path(temporary), wheels))

    def test_out_of_range_coordinate_is_rejected(self) -> None:
        wheels = [{"number": 1, "lat": 91, "lng": 135, "image": "wheels/w001.png"}]
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(CatalogError, "outside -90..90"):
                load_catalog(write_catalog(Path(temporary), wheels))

    def test_repository_images_and_catalog_validate_together(self) -> None:
        result = subprocess.run(
            [sys.executable, "-B", "scripts/validate-wheels.py"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Validated 36 wheel records and 36 PNG images.", result.stdout)


if __name__ == "__main__":
    unittest.main()
