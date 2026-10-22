#!/usr/bin/env python3
"""Generate macOS icon assets from Packaging/AppIcon.svg.

Requires macOS command-line tools and librsvg (brew install librsvg).
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PACKAGING_DIR = PROJECT_ROOT / "Packaging"
SOURCE_PATH = PACKAGING_DIR / "AppIcon.svg"
MASTER_PATH = PACKAGING_DIR / "AppIcon-master.png"
ICONSET_DIR = PACKAGING_DIR / "AppIcon.iconset"
ICNS_PATH = PACKAGING_DIR / "AppIcon.icns"


def main() -> None:
    renderer = shutil.which("rsvg-convert")
    if renderer is None:
        raise SystemExit("Install the SVG renderer first: brew install librsvg")
    subprocess.run([
        renderer, "--width", "1024", "--height", "1024",
        "--output", str(MASTER_PATH), str(SOURCE_PATH),
    ], check=True)
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, size in sizes.items():
        subprocess.run([
            "sips", "--resampleHeightWidth", str(size), str(size),
            str(MASTER_PATH), "--out", str(ICONSET_DIR / filename),
        ], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([
        "iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(ICNS_PATH),
    ], check=True)
    print(ICNS_PATH)


if __name__ == "__main__":
    main()
