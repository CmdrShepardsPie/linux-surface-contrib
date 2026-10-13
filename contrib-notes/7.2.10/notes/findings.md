# Port findings log (v6.19-surface -> v7.2-surface)

## F1 [P1, pre-existing in 6.19, not introduced by port] hid-multitouch: PM notifier leak on Apple Touch Bar probe failure
- Patch: "hid/multitouch: Turn off Type Cover keyboard backlight when suspending" (Patchset: surface-typecover)
- mt_probe() registers td->pm_notifier, then the MT_CLS_APPLE_TOUCHBAR / !hid_find_field() path returns -ENODEV
  without unregister_pm_notifier(). td is devm-allocated, so it is freed on probe failure while still on the
  PM notifier chain -> use-after-free on next suspend. Only reachable on Apple Touch Bar devices missing that field.
- Plan: separate fix commit at end of series (not silently folded into the original patch); call out in PR.

## F2 [P1 for anyone building 7.2.5+] PR #2233's 7.2 patches no longer apply on v7.2.10
- Base was v7.2.4. Upstream 7.2.5+ added MT_QUIRK_IGNORE_FEATURE_ID_MISMATCH = BIT(26) and
  MT_CLS_ASUS_ROG_Z13_FOLIO = 0x0117 to hid-multitouch.c, the same values #2233 assigns to the Surface Type Cover.
- On v7.2.10: 0010-surface-typecover and 0015-hid-surface FAIL (strict git apply and patch -Np1); 0003-mwifiex
  needs fuzz (lands correctly: BTUSB_LOWER_LESCAN_INTERVAL BIT(30)). Fails loudly; no silent bit collision.
- Fix: renumber to BIT(27)/(28)/(29) and 0x0118/0x0119. Matches an independent resolution of the same clash in a 6.18.56 port.

## F1 also present in PR #2233 (0010-surface-typecover): Apple Touch Bar -ENODEV path skips unregister_pm_notifier.

## F3 [P2, pre-existing since 6.19] Format-string bugs in "Add camera support for Surface Pro 9" (Patchset: cameras)
- drivers/platform/x86/intel/int3472/discrete.c, skl_int3472_handle_gpio_resources():
  - dev_info(..., "  con_id=%s, flags=0x%x\n", con_id, gpio_flags): gpio_flags is unsigned long, so this is -Wformat (should be %lx).
  - dev_err(..., "Failed to register type 0x02x: %d\n", type, ret): missing '%' (should be 0x%02x), so the message prints the
    literal "0x02x", formats `type` as %d, and drops `ret` (-Wformat-extra-args). Error reports from this path are misleading.
- Both warnings appear in normal builds, not just W=1. No functional impact beyond log output.

## Method note (my error, fixed): per-commit build v1 reused one .config across checkouts. syncconfig dropped symbols
## that didn't exist at early commits (e.g. HID_IPTS), so later commits built nothing for their new drivers. v2 restores
## the merged config before every commit and fails any commit whose C targets produced zero compile lines.

## F4 [P3/nit, pre-existing, W=1 only] drivers/hid/ipts/desc.h defines static const descriptors
## (ipts_singletouch_descriptor, ipts_fallback_descriptor) that some including .c files don't use
## -> -Wunused-const-variable. Cosmetic.

## Per-commit build r0 (v2 method): 40/40 commits build; 38 compile their touched C files (W=1), 2 have no C files
## (NX revert = header.S/Kconfig; tps68470 masks = header only; both covered by full build). Warnings only F3 (2) and F4 (7).

## F5 [P3/nit, pre-existing since 6.19] sparse: drivers/input/touchscreen/surface3_spi.c 'use_dma' not declared static
## (patch "surface3-spi: workaround: disable DMA mode to avoid crash by default"). Module param variable; should be static.

## sparse (v0.6.5-rc1 built from source; Ubuntu's 0.6.4 is silently skipped by kbuild 7.2 -- caught by checking CHECK lines):
## 53/53 touched C files checked on refresh, 32/32 on vanilla. Only new finding: F5.
## checkpatch: 208 findings on #2233@7.2.4 and 208 identical on refresh -> refresh adds zero.
full kernel build of r4-final with linux-surface's CI config: OK (make all; the first attempt stopped only at vmlinux.bin.zst because zstd wasn't installed in the build container; make bzImage then succeeded).
