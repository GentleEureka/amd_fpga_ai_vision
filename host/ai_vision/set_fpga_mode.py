#!/usr/bin/env python3
"""Set an OV5640 image effect through the FPGA over the X520 raw-Ethernet link."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


CAMERA_VIEWER = Path(__file__).resolve().parents[1] / "camera_viewer"
sys.path.insert(0, str(CAMERA_VIEWER))

from fpga_algorithm_control import FpgaAlgorithmController, MODE_NAMES  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("color", "gray", "binary", "blackwhite", "invert"))
    parser.add_argument("--interface", default=None)
    args = parser.parse_args()
    request = FpgaAlgorithmController(args.interface).select(args.mode)
    print(
        "OV5640_IMAGE_MODE_COMMAND_SENT "
        f"mode={request.mode} name={MODE_NAMES[request.mode]} "
        f"threshold={request.threshold} sequence={request.sequence}"
    )


if __name__ == "__main__":
    main()
