#!/usr/bin/env python3
# Copyright 2026 the linux-surface-contrib authors
"""Resolve media commit 8e3def7bf410's context conflict on linux-surface trees.

linux-surface's "Add camera support for Surface Pro 9" adds the OVTI5693 entry right
after INT33BE instead of in sorted order, so upstream's hunk for the sorted position
conflicts. This keeps our side of the conflicted hunk and adds upstream's MATCH_FL entry
just before linux-surface's OVTI5693 entry instead.

Usage: resolve-ncont.py drivers/media/pci/intel/ipu-bridge.c
"""

import re
import sys
from pathlib import Path

PROG = "resolve-ncont.py"
USAGE = f"usage: {PROG} drivers/media/pci/intel/ipu-bridge.c\n"
CONFLICT = re.compile(r"<<<<<<< [^\n]*\n(.*?)=======\n.*?>>>>>>> [^\n]*\n", re.DOTALL)
ENTRY = '\tIPU_SENSOR_CONFIG("OVTI5693", 1, 419200000),\n'
MATCH_FL = (
    '\tIPU_SENSOR_CONFIG_MATCH_FL("OVTI5693", ipu6_ov5693_ncont_clk,\n'
    "\t\t\t\t   IPU_BR_FL_CSI2_CLK_NONCONTINUOUS,\n"
    "\t\t\t\t   1, 419200000),\n"
)


def main() -> int:
    """Rewrite the file given as the only argument; return the exit status."""
    if len(sys.argv) != 2:  # noqa: PLR2004 (the program name and one path)
        sys.stderr.write(USAGE)
        return 2
    path = Path(sys.argv[1])
    text, conflicts = CONFLICT.subn(lambda m: m.group(1), path.read_text())
    if conflicts != 1:
        sys.stderr.write(f"{PROG}: expected one conflict, found {conflicts}\n")
        return 1
    if text.count(ENTRY) != 1:
        sys.stderr.write(f"{PROG}: expected linux-surface's one OVTI5693 entry\n")
        return 1
    path.write_text(text.replace(ENTRY, MATCH_FL + ENTRY))
    return 0


if __name__ == "__main__":
    sys.exit(main())
