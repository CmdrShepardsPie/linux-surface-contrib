# 6.18.56: linux-surface's 6.18 patch set on the latest 6.18 LTS release

Branch `6.18.56-rebase`: upstream `master`'s `patches/6.18` moved from v6.18.18 to v6.18.56,
rebased only. No new fixes and no backports.

## Where the 6.18 patch set stood

- `master`'s `patches/6.18` was last regenerated for **v6.18.18** (2026-03-14). The
  autoupdate branches for 6.18.20 to 6.18.26 (up to 2026-05-01) were never merged.
- linux-surface #2117 (2026-05-09) then added eight "dirtyfrag" security backports
  (`0017`–`0024`).
- So the shipped series is 49 commits on v6.18.18: 41 Surface commits plus the eight
  backports. `verify-series.sh KS v6.18.18 <master's patches/6.18>` gives 49 commits, tree
  `56e0e519a75913d8f818fb18d3a50107ca2e913a`.
- linux-surface/kernel's `v6.18-surface` branch (tag `surface/v6.18.26`) has the same 41
  Surface commits on v6.18.26 (`git range-diff`: all 41 identical), without the backports.

## The rebase

| | |
|---|---|
| Result | 41 commits on v6.18.56, tree `79cabb2b76bac449519ed19b210cbe975c4dfd8f` |
| Patch files | 16 (the eight dirtyfrag files removed) |
| Reproduce | `update-series.sh` (below), or `verify-series.sh KS v6.18.56 patches/6.18 79cabb2b…` on the branch |

Six commits conflicted. Each is resolved the way #2233's 7.2 series resolves the same
upstream change:

- **btusb** ("Lower passive lescan interval on Marvell 88W8897"): stable took `BIT(29)` for
  `BTUSB_BROKEN_EXT_SCAN`; `BTUSB_LOWER_LESCAN_INTERVAL` moves to `BIT(30)`.
- **mei** ("Add Icelake device ID for iTouch"): stable renamed `MEI_DEV_ID_*` to
  `PCI_DEVICE_ID_INTEL_MEI_*` and uses `PCI_DEVICE_DATA()`; the two added lines take that form.
- **intel-iommu** ("Use IOMMU passthrough mode for IPTS"): context only; stable added the
  Q35 quirk line, and `quirk_iommu_ipts()` goes before it.
- **hid-multitouch**, three commits ("Turn off Type Cover keyboard backlight when
  suspending", "Add support for surface pro type cover tablet switch", "Prevent mode set on
  Surface Laptop Studio 2 touch pad"): stable took `BIT(26)` for
  `MT_QUIRK_IGNORE_FEATURE_ID_MISMATCH` and `0x0117` for `MT_CLS_ASUS_ROG_Z13_FOLIO`, and uses
  `timer_shutdown_sync()` in `mt_remove()`. The Surface quirks move to `BIT(27)`–`BIT(29)` and
  their classes to `0x0118`–`0x0119`; `mt_remove()` unregisters the PM notifier before
  `timer_shutdown_sync()` and keeps the tablet-mode reset on disconnect.

## Why the dirtyfrag backports are left out

All eight are already in v6.18.56, as stable's own backports of the same upstream commits:

| #2117 patch | In v6.18.56 as |
|---|---|
| 0017 xfrm: esp: avoid in-place decrypt on shared skb frags | `71a1d9d985` |
| 0018 rxrpc: Fix potential UAF after skb_unshare() failure | `996b0487b3` |
| 0019 rxrpc: Fix rxrpc_input_call_event() to only unshare DATA packets | `761c37b761` |
| 0020 rxrpc: Fix use of wrong skb when comparing queued RESP challenge serial | `9132b1a7bf` |
| 0021 rxrpc: only handle RESPONSE during service challenge | `d0035e634d` |
| 0022 rxrpc: Fix conn-level packet handling to unshare RESPONSE packets | `ca71ac2de3` |
| 0023 rxrpc: Fix re-decryption of RESPONSE packets | `76cb9a2d25` |
| 0024 rxrpc: Also unshare DATA/RESPONSE packets when paged frags are present | `3eae0f4f9f` |

Later stable commits then reworked the same code: `46cb765e2e` (rxrpc copies DATA into a
buffer in recvmsg before decrypting, `call->rx_dec_buffer`), `8bf7dbb741` (RESPONSE
verification extracts the skb to a linear buffer), and `c093468aea` and `6cab554f2c` (ESP).
That's why only two of the eight come out as empty commits when re-applied; the other six
would apply a second time on top of the reworked code. (Each commit ID was checked as an
ancestor of v6.18.56 with that subject. An earlier version of these notes said stable had
fixed Dirty Frag "its own way"; it carries these exact fixes. The `6.18.56-rebase` commit
message still says so and gets corrected when the branch is offered upstream.)

The run that produced the branch left the six with `--drop`:

```bash
contrib-notes/update-series.sh --out /tmp/upd618 \
  --drop "rxrpc: Fix potential UAF after skb_unshare() failure" \
  --drop "rxrpc: Fix rxrpc_input_call_event() to only unshare DATA packets" \
  --drop "rxrpc: only handle RESPONSE during service challenge" \
  --drop "rxrpc: Fix conn-level packet handling to unshare RESPONSE packets" \
  --drop "rxrpc: Fix re-decryption of RESPONSE packets" \
  --drop "rxrpc: Also unshare DATA/RESPONSE packets when paged frags are present" \
  KS <master's patches/6.18> v6.18.18 v6.18.56
```

## Checks

| Check | Result |
|---|---|
| `git am` of the patch files onto v6.18.56 | 41 commits, tree `79cabb2b…` |
| `update-series.sh` from master's `patches/6.18` (v6.18.18) | same 41 commits and tree; found the two empty commits by itself; stopped at the same six conflicts |
| per-commit build, W=1, merged CI config (`percommit-build.sh`) | 41/41 build (39 compile their C files, 2 have none); warnings only the pre-existing F3 (2, int3472 format strings in "Add camera support for Surface Pro 9") and F4 (7, unused IPTS descriptors), as on 7.2 |
| full `make all`, merged CI config (`full-build.sh`) | rc 0, 3 h 4 min on 2 CPUs; warnings only F3's two |
| sparse (0.6.5-rc1 from source) on the touched C files, against vanilla v6.18.56 | 54/54 touched files checked on the series, 33/33 of those that exist in vanilla checked there; the only finding the series adds is the pre-existing F5 (`use_dma` not static, in "surface3-spi: workaround: disable DMA mode to avoid crash by default"), as on 7.2 |

Not done: KUnit, a boot in QEMU, a boot on a device.

## Updating to the next point release

```bash
git clone --filter=blob:none https://github.com/linux-surface/kernel ks
mkdir /tmp/p && git archive 6.18.56-rebase patches/6.18 | tar -x -C /tmp/p
contrib-notes/update-series.sh --out /tmp/upd ks /tmp/p/patches/6.18 v6.18.56
# conflicts: resolve in the worktree it names, git add, then
#   contrib-notes/update-series.sh --continue ks /tmp/upd
cp /tmp/upd/patches/*.patch patches/6.18/
```

Without a target it takes the newest v6.18.N tag. It writes the patch files' `index` lines
with 12-character blob abbreviations, so the files are the same in any clone; the branch's
files were written before that, with git's default (9 characters in that clone). The
content and the tree are the same either way: a re-run on 2026-10-13 gave tree `79cabb2b…`
again, with the same two commits found already in v6.18.56. `report.txt` lists what became empty,
what was dropped and which commits needed a hand resolution; add `--percommit CONFIG` and
`--full CONFIG` for the build checks.
