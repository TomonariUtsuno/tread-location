#!/usr/bin/env python3
"""Validate canonical wheel data and every referenced PNG without dependencies."""

from __future__ import annotations

import argparse
import binascii
from pathlib import Path
import struct
import sys
from typing import BinaryIO
import zlib

from wheels_data import CatalogError, load_catalog


ROOT = Path(__file__).resolve().parent.parent
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class ImageError(ValueError):
    """Raised when a wheel image does not match the canonical PNG specification."""


def _read_exact(handle: BinaryIO, size: int, image: Path) -> bytes:
    value = handle.read(size)
    if len(value) != size:
        raise ImageError(f"{image}: truncated PNG file")
    return value


def validate_png(image: Path) -> None:
    """Check PNG signature, chunk CRCs, and the required RGB 533x800 IHDR."""
    try:
        with image.open("rb") as handle:
            if _read_exact(handle, len(PNG_SIGNATURE), image) != PNG_SIGNATURE:
                raise ImageError(f"{image}: not a PNG file")

            seen_ihdr = False
            seen_iend = False
            idat_parts: list[bytes] = []
            width = height = color_type = None
            while not seen_iend:
                length = struct.unpack(">I", _read_exact(handle, 4, image))[0]
                chunk_type = _read_exact(handle, 4, image)
                data = _read_exact(handle, length, image)
                expected_crc = struct.unpack(">I", _read_exact(handle, 4, image))[0]
                actual_crc = binascii.crc32(chunk_type + data) & 0xFFFFFFFF
                if actual_crc != expected_crc:
                    raise ImageError(f"{image}: invalid PNG CRC in {chunk_type.decode('ascii', 'replace')}")

                if not seen_ihdr:
                    if chunk_type != b"IHDR" or len(data) != 13:
                        raise ImageError(f"{image}: PNG must begin with a valid IHDR chunk")
                    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
                        ">IIBBBBB", data
                    )
                    if (width, height) != (533, 800):
                        raise ImageError(f"{image}: expected 533x800 px, found {width}x{height} px")
                    if (bit_depth, color_type) != (8, 2):
                        raise ImageError(f"{image}: expected 8-bit RGB PNG without alpha")
                    if (compression, filtering, interlace) != (0, 0, 0):
                        raise ImageError(f"{image}: unsupported PNG encoding")
                    seen_ihdr = True

                if chunk_type == b"IDAT":
                    idat_parts.append(data)

                if chunk_type == b"IEND":
                    if data:
                        raise ImageError(f"{image}: IEND chunk must be empty")
                    seen_iend = True

            if handle.read(1):
                raise ImageError(f"{image}: trailing data after IEND")

            if not idat_parts:
                raise ImageError(f"{image}: PNG has no image data")
            try:
                scanlines = zlib.decompress(b"".join(idat_parts))
            except zlib.error as error:
                raise ImageError(f"{image}: unreadable compressed PNG data") from error
            row_size = 1 + width * 3
            if len(scanlines) != height * row_size:
                raise ImageError(f"{image}: PNG pixel data has an unexpected length")
            if any(scanlines[offset] > 4 for offset in range(0, len(scanlines), row_size)):
                raise ImageError(f"{image}: PNG uses an invalid scanline filter")
    except OSError as error:
        raise ImageError(f"{image}: cannot read image ({error})") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.root.resolve()

    try:
        catalog = load_catalog(root / "wheels.json")
        referenced = {wheel.image for wheel in catalog.wheels}
        image_root = root / "wheels"
        if not image_root.is_dir():
            raise ImageError(f"{image_root}: directory does not exist")

        for relative_path in referenced:
            image = root / relative_path
            if not image.is_file():
                raise ImageError(f"missing referenced image: {relative_path}")
            validate_png(image)

        actual = {
            path.relative_to(root).as_posix()
            for path in image_root.rglob("*")
            if path.is_file()
        }
        missing = sorted(referenced - actual)
        unused = sorted(actual - referenced)
        if missing:
            raise ImageError(f"missing referenced images: {', '.join(missing)}")
        if unused:
            raise ImageError(f"unused images: {', '.join(unused)}")
    except (CatalogError, ImageError) as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        return 1

    print(f"Validated {len(catalog.wheels)} wheel records and {len(referenced)} PNG images.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
