#!/usr/bin/env bash
# verify-series.sh KERNEL_TREE BASE_TAG PATCH_DIR [EXPECTED_TREE]: apply PATCH_DIR/*.patch,
# in file order, onto BASE_TAG of linux-surface/kernel in a temporary worktree of
# KERNEL_TREE, and print the number of commits and the resulting tree ID. With
# EXPECTED_TREE, exit 1 unless the tree matches.
#
# KERNEL_TREE: a clone of https://github.com/linux-surface/kernel that has BASE_TAG (for
# example: git clone --filter=blob:none https://github.com/linux-surface/kernel).
# PATCH_DIR: a branch's patches/<version> folder, e.g. from
#   git archive 7.2-fixes patches/7.2 | tar -x -C /tmp/x
set -euo pipefail
shopt -s inherit_errexit
usage="usage: verify-series.sh KERNEL_TREE BASE_TAG PATCH_DIR [EXPECTED_TREE]"
ktree=$(cd "${1:?${usage}}" && pwd)
base=${2:?${usage}}
patches=$(cd "${3:?${usage}}" && pwd)
expected=${4:-}
# A placeholder identity for the temporary commits.
id_email=verify@example.invalid # privacy-scan: allow (reserved .invalid address, no person)
wt=$(mktemp -d)
cleanup() { git -C "${ktree}" worktree remove --force "${wt}" 2>/dev/null || rm -rf "${wt}"; }
trap cleanup EXIT
git -C "${ktree}" worktree add -q --detach "${wt}" "${base}"
git -C "${wt}" -c user.name=verify -c user.email="${id_email}" am -q --whitespace=nowarn \
  "${patches}"/*.patch
n=$(git -C "${wt}" rev-list --count "${base}..HEAD")
tree=$(git -C "${wt}" rev-parse 'HEAD^{tree}')
echo "commits: ${n}"
echo "tree: ${tree}"
if [[ -n ${expected} && ${tree} != "${expected}" ]]; then
  echo "verify-series.sh: tree differs from ${expected}" >&2
  exit 1
fi
