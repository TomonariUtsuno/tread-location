#!/usr/bin/env python3
"""Generate the browser-compatible data.js file from wheels.json."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from wheels_data import CatalogError, load_catalog, render_data_js


ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail when data.js is not current")
    parser.add_argument("--input", type=Path, default=ROOT / "wheels.json")
    parser.add_argument("--output", type=Path, default=ROOT / "data.js")
    args = parser.parse_args()

    try:
        rendered = render_data_js(load_catalog(args.input))
    except CatalogError as error:
        print(f"Catalog validation failed: {error}", file=sys.stderr)
        return 1

    try:
        existing = args.output.read_text(encoding="utf-8")
    except OSError:
        existing = None

    if args.check:
        if existing != rendered:
            print(
                f"{args.output} is not generated from {args.input}; "
                "run scripts/generate-data-js.py",
                file=sys.stderr,
            )
            return 1
        print(f"{args.output} is current.")
        return 0

    args.output.write_text(rendered, encoding="utf-8")
    print(f"Generated {args.output} from {args.input}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
