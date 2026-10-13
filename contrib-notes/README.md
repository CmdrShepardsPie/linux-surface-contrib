# contrib-notes

Working notes and scripts for the `7.2.10-refresh` branch. Upstream wouldn't take this folder;
a pull request to linux-surface leaves it out.

## The branch

`7.2.10-refresh` starts from linux-surface pull request #2233 (the 7.2 patch set, on v7.2.4,
from its author's fork branch `7.2`) and adds, in linux-surface's own layout:

1. **`patches: Rebase patches for v7.2.10`**: the 40 patches of #2233 rebased onto v7.2.10.
   The only change beyond context: upstream 7.2.5+ took BIT(26) and class 0x0117 in
   hid-multitouch, so the surface-typecover and hid-surface patches move to BIT(27)-BIT(29)
   and 0x0118-0x0119 (`notes/findings.md`, F2).
2. **Ten fix commits**, one per fix, each adding one commit at the end of its patch set
   (`surface3`, `surface-typecover`, `cameras`). They fix bugs found while reviewing the
   series (`notes/findings.md`). Each fix patch carries the author's `From:` and
   `Signed-off-by:`, as upstream requires.

`configs/surface-7.2.config` is #2233's and is unchanged: neither the rebase nor the fixes
add configuration symbols.

## Verify

The patches apply with `git am`, in file order, onto tag `v7.2.10` of
https://github.com/linux-surface/kernel (commit `7b20d05fd38de8e0be168956f6fd241d750c7d69`):

| State | Commits | Tree ID |
|---|---|---|
| after the rebase commit | 40 | `c43d1e7a1900f395d086e9c04a8117299955fe1e` |
| after the ten fixes | 50 | `0d91cbf4e2a3ddfa018a033f245fbd78febbd1b7` |

```bash
git clone --filter=blob:none https://github.com/linux-surface/kernel ks
contrib-notes/scripts/verify-series.sh ks 0d91cbf4e2a3ddfa018a033f245fbd78febbd1b7
```

`git am` warns about blank lines at the end of some new files; they come from the upstream
patches.

## Regenerate

`scripts/genpatchsets.sh` rebuilds every step's patch files from the full series in a kernel
tree (`FIX_AUTHOR` names the fixes' author). With a fixed committer and date, the output is
the same on every run, so a regenerated step can be compared with the branch file by file.
Each fix commit takes only its patch set's file from its step; the other files keep the
rebase commit's version, which differs from a fresh generation only in the informational
`From <commit-id>` lines.

`verify-series.sh` and `genpatchsets.sh` pass `shellcheck --enable=all`. The other scripts
are kept as they were run during the review and haven't been brought to that standard.

## Status

Done:
- every commit builds on its own with W=1 (`scripts/percommit-build.sh`);
- no new checkpatch or sparse findings (`notes/`);
- KUnit matches vanilla, 23/23 (`scripts/run-kunit.sh`, `scripts/surface.kunitconfig`);
- the full `make all` with linux-surface's CI configuration passes
  (`scripts/merged-7.2.10.config`, `scripts/full-build.sh`);
- five review rounds, the last one clean.

Not done:
- the Arch package bump to 7.2.10.arch1 (`pkg/arch/kernel`), which #2233 carries for 7.2.4;
- KUnit on the final tip, a QEMU boot, and a test on a real device.

Nothing here has been posted upstream or pushed to a public fork.
