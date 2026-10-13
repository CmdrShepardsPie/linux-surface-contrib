# Front camera (OV5693) backport

## What it is

The Surface Pro 7+, 8 and 9 and the Go 4 front camera (an OV5693 on an Intel IPU6) streams
no frames on linux-surface kernels, because the IPU6's CSI-2 receiver needs the sensor to
gate its MIPI clock lane between packets. The fix is in the media tree, in branch `next` of
https://gitlab.freedesktop.org/linux-media/media-committers (series "media: Enable the
OV5693 front camera on IPU6 Surface devices", v5, by Fernando Rimoli; applied 2026-09-11):

| Upstream commit | Change | Backported |
|---|---|---|
| `df7980112cee` | ov5693: Add OVTI5693 ACPI HID | no: linux-surface already has it ("Add camera support for Surface Pro 9") |
| `b304130a403c` | ipu-bridge: Add OVTI5693 to the list of supported sensors | no: same, it would duplicate the entry |
| `8fe9836a1ef8` | dt-bindings: ov5693: Add clock-noncontinuous | no: device tree only |
| `eda381fd8c0c` | ipu-bridge: Add ipu_bridge_get_ipu6() | yes, as a prerequisite: `8e3def7bf410` uses the IPU6 PCI IDs from `<media/ipu6-pci-table.h>`, which this commit includes |
| `0e12587945f6` | ov5693: Gate the MIPI clock lane for non-continuous clock | yes |
| `3436405beac8` | ipu-bridge: Assign endpoint property indices dynamically | yes |
| `b883954d842f` | ipu-bridge: Match sensor configs per IPU and add config flags | yes |
| `8e3def7bf410` | ipu-bridge: Request non-continuous clock for ov5693 on IPU6 | yes, with one context fix-up (below) |
| `a20c843c9bc4` | ipu-bridge: Keep the clock-noncontinuous property name out of rodata | yes (fixes `8e3def7bf410`) |

Each backported commit keeps its author and tags and gains `(cherry picked from commit
<id>)` and the cameras patch set's `Patchset: cameras` trailer. `eda381fd8c0c` and
`8e3def7bf410` also carry a `[ backport: … ]` note saying why they're there or what changed.

**The fix-up in `8e3def7bf410`.** linux-surface's "Add camera support for Surface Pro 9" lists
`OVTI5693` right after `INT33BE` rather than in sorted order, so upstream's hunk for the
sorted position conflicts. The new `OVTI5693` `MATCH_FL` entry goes just before
linux-surface's entry instead; the IPU-specific entry still comes before the plain one, as
the matching requires. `resolve-ncont.py` makes exactly that change on the conflicted file.

## Checked

For each base: apply the six commits in order with `git am --3way` (the fix-up for
`8e3def7bf410`), then at every commit build `drivers/media/pci/intel/ipu-bridge.o` and
`drivers/media/i2c/ov5693.o` with `W=1` and sparse (`C=1`, sparse built from source), using
`../7.2.10/scripts/merged-7.2.10.config` after `olddefconfig` (`CONFIG_IPU_BRIDGE=m`,
`CONFIG_VIDEO_OV5693=m`). Every commit built with no warnings on each base:

- `v6.19.8` with linux-surface `master`'s `patches/6.19` (branch `6.19-ov5693-ncont`);
- `v7.2.4` with #2233's `patches/7.2` (branch `7.2-ov5693-ncont`);
- `v7.2.10` with `7.2.10-refresh`'s series (the rebase and the fixes): the commits apply
  the same way, for whoever wants them on top of that.

Then the branches' patch files were applied with `git am` onto `v6.19.8` and `v7.2.4` and
reproduce the trees listed in `../README.md`.

Not checked yet: a boot and capture on a real Surface Pro 9 (planned: two captures per boot
over several cold boots, and `MIPI_CTRL00`, register `0x4800`, reading `0x20`). The series'
author reports 300/300 frames at 28.6 fps on a Pro 9 with the upstream series.
