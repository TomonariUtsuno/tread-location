#!/usr/bin/env python3
"""Parse the one-line coordinate formats accepted by the future updater UI."""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
import re
from typing import Literal
import unicodedata


class CoordinateError(ValueError):
    """Raised when a coordinate input cannot be safely interpreted."""


@dataclass(frozen=True)
class Coordinates:
    """Decimal-degree coordinates ready for storage in wheels.json."""

    lat: Decimal
    lng: Decimal
    input_format: Literal["dms", "decimal"]
    warnings: tuple[str, ...] = ()


_SYMBOLS = str.maketrans(
    {
        "　": " ",
        "，": ",",
        "、": ",",
        "º": "°",
        "˚": "°",
        "′": "'",
        "’": "'",
        "‘": "'",
        "＇": "'",
        "`": "'",
        "″": '"',
        "“": '"',
        "”": '"',
        "＂": '"',
    }
)
_DECIMAL_PAIR = re.compile(
    r"^\s*(?P<lat>[+-]?\d+(?:\.\d+)?)\s*,\s*(?P<lng>[+-]?\d+(?:\.\d+)?)\s*$"
)
_DMS_PAIR = re.compile(
    r"""^\s*
    (?P<first_direction>[NSEW])\s*
    (?P<first_degrees>\d{1,3})\s*°\s*
    (?P<first_minutes>\d+(?:\.\d+)?)\s*'\s*
    (?P<first_seconds>\d+(?:\.\d+)?)\s*"\s*
    ,?\s*
    (?P<second_direction>[NSEW])\s*
    (?P<second_degrees>\d{1,3})\s*°\s*
    (?P<second_minutes>\d+(?:\.\d+)?)\s*'\s*
    (?P<second_seconds>\d+(?:\.\d+)?)\s*"\s*$
    """,
    re.VERBOSE,
)


def normalize_coordinate_input(value: str) -> str:
    """Normalize harmless Unicode punctuation and whitespace, without guessing values."""
    if not isinstance(value, str):
        raise CoordinateError("coordinate input must be text")
    normalized = unicodedata.normalize("NFKC", value.translate(_SYMBOLS)).translate(_SYMBOLS)
    return " ".join(normalized.upper().split())


def validate_decimal_coordinates(lat: Decimal, lng: Decimal) -> None:
    """Validate decimal degrees without changing their ordering or sign."""
    if not Decimal("-90") <= lat <= Decimal("90"):
        if Decimal("-180") <= lat <= Decimal("180") and Decimal("-90") <= lng <= Decimal("90"):
            raise CoordinateError(
                "first value is outside latitude range; latitude and longitude may be reversed"
            )
        raise CoordinateError("latitude is outside -90..90")
    if not Decimal("-180") <= lng <= Decimal("180"):
        raise CoordinateError("longitude is outside -180..180")


def _decimal(value: str, label: str) -> Decimal:
    try:
        result = Decimal(value)
    except InvalidOperation as error:
        raise CoordinateError(f"{label} is not a number") from error
    if not result.is_finite():
        raise CoordinateError(f"{label} must be finite")
    return result


def _dms_to_decimal(direction: str, degrees_text: str, minutes_text: str, seconds_text: str) -> Decimal:
    degrees = _decimal(degrees_text, "degrees")
    minutes = _decimal(minutes_text, "minutes")
    seconds = _decimal(seconds_text, "seconds")
    if minutes >= Decimal("60"):
        raise CoordinateError("minutes must be less than 60")
    if seconds >= Decimal("60"):
        raise CoordinateError("seconds must be less than 60")
    result = degrees + minutes / Decimal("60") + seconds / Decimal("3600")
    return -result if direction in {"S", "W"} else result


def parse_coordinate_input(value: str) -> Coordinates:
    """Parse DMS or latitude/longitude decimal input without silently reordering it.

    DMS requires cardinal directions, such as ``N34°31'22.98" E135°36'27.93"``.
    Decimal input is explicitly interpreted as ``latitude, longitude``.
    """
    normalized = normalize_coordinate_input(value)
    if not normalized:
        raise CoordinateError("coordinate input is empty")

    decimal_match = _DECIMAL_PAIR.fullmatch(normalized)
    if decimal_match:
        lat = _decimal(decimal_match["lat"], "latitude")
        lng = _decimal(decimal_match["lng"], "longitude")
        validate_decimal_coordinates(lat, lng)
        return Coordinates(
            lat=lat,
            lng=lng,
            input_format="decimal",
            warnings=(
                "Decimal input has no cardinal directions; interpreted as latitude, longitude. "
                "Confirm the preview before publishing.",
            ),
        )

    dms_match = _DMS_PAIR.fullmatch(normalized)
    if not dms_match:
        raise CoordinateError(
            "use N/S/E/W DMS (for example N34°31'22.98\" E135°36'27.93\") "
            "or decimal latitude, longitude"
        )

    components = []
    for side in ("first", "second"):
        direction = dms_match[f"{side}_direction"]
        coordinate = _dms_to_decimal(
            direction,
            dms_match[f"{side}_degrees"],
            dms_match[f"{side}_minutes"],
            dms_match[f"{side}_seconds"],
        )
        components.append((direction, coordinate))

    latitude = [coordinate for direction, coordinate in components if direction in {"N", "S"}]
    longitude = [coordinate for direction, coordinate in components if direction in {"E", "W"}]
    if len(latitude) != 1 or len(longitude) != 1:
        raise CoordinateError("DMS input must contain exactly one N/S value and one E/W value")
    validate_decimal_coordinates(latitude[0], longitude[0])
    return Coordinates(lat=latitude[0], lng=longitude[0], input_format="dms")
