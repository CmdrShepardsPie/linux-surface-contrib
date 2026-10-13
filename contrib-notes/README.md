# contrib-notes

Notes, checks and scripts for this repository's topic branches. This `notes` branch holds
them so that the topic branches carry only what a linux-surface pull request would contain.
Nothing here is meant for upstream.

**AI assistance.** The branches and notes in this fork were prepared with AI assistance
(Claude) and checked before publishing; commits from upstream contributors are theirs. New
commits carry an `Assisted-by:` trailer in the format of the kernel's
`Documentation/process/coding-assistants.rst` (v7.2). Patches offered upstream follow that
document: the AI tool is named in `Assisted-by:`, and only the human submitter adds
`Signed-off-by:`.

## Branches

Each topic branch changes linux-surface's own layout (`patches/<version>/`, `configs/`) and
can be taken on its own unless it says it's stacked. All of them use one commit per change,
and each patch they add goes at the end of its patch-set file, so the existing patches in
that file are untouched.

| Branch | Based on | What it adds | Commits after `git am` on | Tree ID after `git am` |
|---|---|---|---|---|
| `master` | upstream `master` | (upstream's history, unchanged) | | |
| `7.2.10-rebase` | #2233's head `6bcf30a1f` | the 7.2 patch set rebased onto v7.2.10 | 40 on `v7.2.10` | `c43d1e7a1900f395d086e9c04a8117299955fe1e` |
| `7.2-fixes` | #2233's head `6bcf30a1f` | ten bug fixes, one commit each, on #2233's 7.2.4 patch set | 50 on `v7.2.4` | `10c5f9a60ca6f6ead60a72c328baa41e168bd61b` |
| `7.2.10-refresh` | #2233's head `6bcf30a1f` | **stacked:** the rebase, then the same ten fixes regenerated on v7.2.10 | 50 on `v7.2.10` | `0d91cbf4e2a3ddfa018a033f245fbd78febbd1b7` |
| `7.2-ov5693-ncont` | #2233's head `6bcf30a1f` | the front-camera backport (below) on #2233's 7.2.4 patch set | 46 on `v7.2.4` | `f8501be7c0c42809e134d769ec49b10bc5f5a8b4` |
| `6.19-ov5693-ncont` | upstream `master` | the same backport on the shipped 6.19 patch set | 55 on `v6.19.8` | `83c5eb68f73d18af6a29d6550be6fbb6409f2624` |
| `6.18.56-rebase` | upstream `master` | the 6.18 patch set moved from v6.18.18 to v6.18.56, rebased only (see `6.18.56/`) | 41 on `v6.18.56` | `79cabb2b76bac449519ed19b210cbe975c4dfd8f` |

**Why `7.2.10-refresh` is stacked.** The fixes don't depend on the rebase as code: each of
them applies to #2233's 7.2.4 patch set as it is (`7.2-fixes`). But the rebase and the
fixes both rewrite the same patch files (`0002-surface3`, `0010-surface-typecover`,
`0013-cameras`), so git can't merge `7.2.10-rebase` and `7.2-fixes` together.
`7.2.10-refresh` is that combination, for whoever wants both on v7.2.10. The same goes for
the camera backport: `7.2-ov5693-ncont` adds to `0013-cameras.patch` like `7.2-fixes` does,
and taking several of these branches means regenerating that file once. The backport's
commits also apply and build on the 7.2.10 series with the fixes (checked, see below).

`verify-series.sh` reproduces the table's last two columns from a branch's patch files, for
example:

```bash
git clone --filter=blob:none https://github.com/linux-surface/kernel ks
mkdir /tmp/x && git archive 7.2-fixes patches/7.2 | tar -x -C /tmp/x
contrib-notes/verify-series.sh ks v7.2.4 /tmp/x/patches/7.2 10c5f9a60ca6f6ead60a72c328baa41e168bd61b
```

`git am` warns about blank lines at the end of some new files; they come from the upstream
patches.

## Folders

- `update-series.sh`: moves a patch set to a newer point release in one run (rebase, leave
  out what stable already has, regenerate the patch files, verify them, optionally build).
  `6.18.56/README.md` shows a run. Its tests are in `tests/`: `update-series-tests.sh` (13
  cases on toy repositories) and `mutate-update-series.sh` (9 mutations, all caught).
- `6.18.56/`: the 6.18 LTS rebase, its conflict resolutions and why the dirtyfrag backports
  are left out.

- `7.2.10/`: the 7.2.10 rebase and fixes, with their review notes (`notes/findings.md` lists
  the bugs the fixes address), the per-commit, KUnit and full-build scripts, the merged CI
  configuration, and `genpatchsets.sh`, which regenerates the patch files step by step.
- `ov5693-ncont/`: the front-camera backport.

## Status

Done: everything listed in `7.2.10/` and `ov5693-ncont/` (builds, static checks, the tree IDs
above). Not done: the Arch package bump for 7.2.10, KUnit on the final tips, a boot in QEMU,
and any test on a real device. The branches are offered upstream only after review, and only
in the form the maintainers' process asks for.
