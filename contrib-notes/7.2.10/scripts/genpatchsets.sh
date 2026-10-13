#!/usr/bin/env bash
# genpatchsets.sh KERNEL_TREE TIP OUTROOT: regenerate patches/7.2 for this branch's history.
#
# TIP is the full series in KERNEL_TREE (a clone of linux-surface/kernel), on top of tag
# v7.2.10; its commits authored by FIX_AUTHOR (environment) are the fixes. Writes
# OUTROOT/step0 (the series without the fixes, i.e. the plain rebase) and OUTROOT/stepK (with
# the first K fixes), each holding the patch files from git-format-patchsets
# (https://github.com/qzed/git-tools; GIT_FORMAT_PATCHSETS names it), plus stepK.tree (the
# tree ID) and stepK.fix (the fix's commit ID, subject and patch set).
#
# The tool expects .git to be a directory, so this checks out commits in KERNEL_TREE itself
# and goes back to where it was at the end; KERNEL_TREE must have no local changes.
set -euo pipefail
shopt -s inherit_errexit
usage="usage: FIX_AUTHOR=NAME genpatchsets.sh KERNEL_TREE TIP OUTROOT"
KS=$(cd "${1:?${usage}}" && pwd)
TIP=${2:?${usage}}
OUT=${3:?${usage}}
TOOL=${GIT_FORMAT_PATCHSETS:-git-format-patchsets}
FIX_AUTHOR=${FIX_AUTHOR:?${usage}}
mkdir -p "${OUT}"
OUT=$(cd "${OUT}" && pwd)

revs=$(git -C "${KS}" rev-list --reverse "v7.2.10..${TIP}")
mapfile -t all <<<"${revs}"
fixes=()
for c in "${all[@]}"; do
  author=$(git -C "${KS}" log -1 --format=%an "${c}")
  if [[ ${author} == "${FIX_AUTHOR}" ]]; then fixes+=("${c}"); fi
done
echo "fixes: ${#fixes[@]}"

# A placeholder committer for the regenerated commits.
id_email=builder@example.invalid # privacy-scan: allow (reserved .invalid address, no person)
orig=$(git -C "${KS}" symbolic-ref -q --short HEAD || git -C "${KS}" rev-parse HEAD)
for ((k = 0; k <= ${#fixes[@]}; k++)); do
  git -C "${KS}" checkout -q --detach v7.2.10
  picks=()
  for c in "${all[@]}"; do
    skip=0
    for ((j = k; j < ${#fixes[@]}; j++)); do
      if [[ ${c} == "${fixes[j]}" ]]; then skip=1; fi
    done
    if ((!skip)); then picks+=("${c}"); fi
  done
  # A fixed committer and date make the commit IDs (in each patch's "From <id>" line) the
  # same in every step, up to the first commit that differs.
  GIT_COMMITTER_NAME=builder GIT_COMMITTER_EMAIL=${id_email} \
    GIT_COMMITTER_DATE="2026-10-13T00:00:00Z" git -C "${KS}" cherry-pick "${picks[@]}" >/dev/null
  d=${OUT}/step${k}
  rm -rf "${d}"
  mkdir -p "${d}"
  (cd "${KS}" && EDITOR=true "${TOOL}" -t -a v7.2.10..HEAD >/dev/null && mv ./*.patch "${d}/")
  git -C "${KS}" rev-parse 'HEAD^{tree}' >"${d}.tree"
  if ((k > 0)); then
    git -C "${KS}" log -1 --format='%H%n%s%n%(trailers:key=Patchset,valueonly,separator=)' \
      "${fixes[k - 1]}" >"${d}.fix"
  fi
  echo "step ${k}: ${#picks[@]} commits"
done
git -C "${KS}" checkout -q "${orig}"
