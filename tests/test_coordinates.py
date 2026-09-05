"""Tests for the single-field coordinate input contract."""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from coordinates import CoordinateError, parse_coordinate_input  # noqa: E402


class CoordinateInputTests(unittest.TestCase):
    def test_dms_example_converts_to_decimal_degrees(self) -> None:
        result = parse_coordinate_input('N34°31\'22.98" E135°36\'27.93"')
        self.assertEqual(result.input_format, "dms")
        self.assertEqual(format(result.lat, ".8f"), "34.52305000")
        self.assertEqual(format(result.lng, ".8f"), "135.60775833")

    def test_dms_normalizes_fullwidth_space_and_smart_symbols(self) -> None:
        result = parse_coordinate_input('Ｎ34°31’22.98”　Ｅ135°36′27.93″')
        self.assertEqual(result.lat, Decimal("34.523050"))
        self.assertEqual(result.lng, Decimal("135.6077583333333333333333333"))

    def test_dms_respects_south_west_and_component_order(self) -> None:
        result = parse_coordinate_input('W135°36\'27.93", S34°31\'22.98"')
        self.assertEqual(result.lat, Decimal("-34.523050"))
        self.assertEqual(result.lng, Decimal("-135.6077583333333333333333333"))

    def test_decimal_format_accepts_fullwidth_comma(self) -> None:
        result = parse_coordinate_input("34.52305000， 135.60775833")
        self.assertEqual(result.input_format, "decimal")
        self.assertEqual(result.lat, Decimal("34.52305000"))
        self.assertEqual(result.lng, Decimal("135.60775833"))
        self.assertEqual(len(result.warnings), 1)
        self.assertIn("latitude, longitude", result.warnings[0])

    def test_minutes_and_seconds_must_be_less_than_sixty(self) -> None:
        with self.assertRaisesRegex(CoordinateError, "minutes must be less than 60"):
            parse_coordinate_input('N34°60\'00" E135°36\'27.93"')
        with self.assertRaisesRegex(CoordinateError, "seconds must be less than 60"):
            parse_coordinate_input('N34°31\'60" E135°36\'27.93"')

    def test_reversed_decimal_input_is_not_silently_corrected(self) -> None:
        with self.assertRaisesRegex(CoordinateError, "may be reversed"):
            parse_coordinate_input("135.60775833, 34.52305000")


if __name__ == "__main__":
    unittest.main()
