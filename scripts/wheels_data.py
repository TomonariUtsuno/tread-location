#!/usr/bin/env python3
"""Shared schema validation and deterministic rendering for tread wheel data."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any

from coordinates import CoordinateError, validate_decimal_coordinates

EXPECTED_IMAGE_SPEC = {
    "format": "png",
    "width": Decimal("533"),
    "height": Decimal("800"),
    "colorModel": "RGB",
    "bitDepth": Decimal("8"),
    "alpha": False,
}
CATALOG_KEYS = {"schemaVersion", "imageSpecification", "wheels"}
IMAGE_SPEC_KEYS = set(EXPECTED_IMAGE_SPEC)
WHEEL_KEYS = {"number", "lat", "lng", "image"}
IMAGE_PATH = re.compile(r"wheels/w(\d{3})\.png\Z")


class CatalogError(ValueError):
    """Raised when the canonical wheel catalog does not meet its schema."""


@dataclass(frozen=True)
class Wheel:
    number: int
    lat: Decimal
    lng: Decimal
    image: str


@dataclass(frozen=True)
class Catalog:
    wheels: tuple[Wheel, ...]


def _decimal(value: Any, label: str) -> Decimal:
    if isinstance(value, bool) or not isinstance(value, Decimal) or not value.is_finite():
        raise CatalogError(f"{label} must be a finite JSON number")
    return value


def _require_exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise CatalogError(f"{label} must be an object")
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        details = []
        if missing:
            details.append(f"missing: {', '.join(missing)}")
        if extra:
            details.append(f"unexpected: {', '.join(extra)}")
        raise CatalogError(f"{label} has an invalid shape ({'; '.join(details)})")
    return value


def _decimal_text(value: Decimal) -> str:
    return format(value, "f")


def load_catalog(path: Path) -> Catalog:
    """Load a strictly validated catalog while preserving decimal text precision."""
    try:
        raw = json.loads(path.read_text(encoding="utf-8"), parse_int=Decimal, parse_float=Decimal)
    except (OSError, json.JSONDecodeError) as error:
        raise CatalogError(f"cannot read {path}: {error}") from error

    root = _require_exact_keys(raw, CATALOG_KEYS, "catalog")
    if _decimal(root["schemaVersion"], "schemaVersion") != Decimal("1"):
        raise CatalogError("schemaVersion must be 1")

    specification = _require_exact_keys(root["imageSpecification"], IMAGE_SPEC_KEYS, "imageSpecification")
    for field, expected in EXPECTED_IMAGE_SPEC.items():
        actual = specification[field]
        if isinstance(expected, Decimal):
            actual = _decimal(actual, f"imageSpecification.{field}")
        if actual != expected:
            raise CatalogError(
                f"imageSpecification.{field} must be {expected!r}, not {actual!r}"
            )

    if not isinstance(root["wheels"], list) or not root["wheels"]:
        raise CatalogError("wheels must be a non-empty array")

    wheels: list[Wheel] = []
    numbers: set[int] = set()
    images: set[str] = set()
    for position, raw_wheel in enumerate(root["wheels"], start=1):
        wheel = _require_exact_keys(raw_wheel, WHEEL_KEYS, f"wheels[{position}]")
        raw_number = _decimal(wheel["number"], f"wheels[{position}].number")
        if raw_number != raw_number.to_integral_value() or not 1 <= raw_number <= 999:
            raise CatalogError(f"wheels[{position}].number must be an integer from 1 to 999")
        number = int(raw_number)
        if number in numbers:
            raise CatalogError(f"duplicate wheel number: {number}")

        lat = _decimal(wheel["lat"], f"wheels[{position}].lat")
        lng = _decimal(wheel["lng"], f"wheels[{position}].lng")
        try:
            validate_decimal_coordinates(lat, lng)
        except CoordinateError as error:
            raise CatalogError(f"wheels[{position}]: {error}") from error

        image = wheel["image"]
        if not isinstance(image, str):
            raise CatalogError(f"wheels[{position}].image must be a string")
        match = IMAGE_PATH.fullmatch(image)
        if not match:
            raise CatalogError(f"wheels[{position}].image must use wheels/wNNN.png")
        if image in images:
            raise CatalogError(f"duplicate image path: {image}")
        if int(match.group(1)) != number:
            raise CatalogError(
                f"wheels[{position}].image must use the same number as the record"
            )

        wheels.append(Wheel(number=number, lat=lat, lng=lng, image=image))
        numbers.add(number)
        images.add(image)

    return Catalog(wheels=tuple(wheels))


def render_data_js(catalog: Catalog) -> str:
    """Render the historical browser data file without changing record order."""
    lines = ["window.TREAD_WHEELS = Object.freeze(["]
    last_index = len(catalog.wheels) - 1
    for index, wheel in enumerate(catalog.wheels):
        suffix = "," if index != last_index else ""
        lines.append(
            f'  {{ number: {wheel.number}, lat: {_decimal_text(wheel.lat)}, '
            f'lng: {_decimal_text(wheel.lng)}, image: "{wheel.image}" }}{suffix}'
        )
    lines.append("]);\n")
    return "\n".join(lines)
