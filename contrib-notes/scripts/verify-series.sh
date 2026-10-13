#!/usr/bin/env bash
# verify-series.sh KERNEL_TREE [EXPECTED_TREE]: apply patches/7.2/*.patch, in file order, onto
# tag v7.2.10 of linux-surface/kernel in a temporary worktree of KERNEL_TREE, and print the
# resulting tree ID. With EXPECTED_TREE, exit 1 unless they match.
#
# KERNEL_TREE: a clone of https://github.com/linux-surface/kernel that has the v7.2.10 tag
# (for example: git clone --filter=blob:none https://github.com/linux-surface/kernel).
set -euo pipefail
shopt -s inherit_errexit
ktree=$(cd "${1:?usage: verify-series.sh KERNEL_TREE [EXPECTED_TREE]}" && pwd)
expected=${2:-}
patches=$(cd "$(dirname "$0")/../../patches/7.2" && pwd)
wt=$(mktemp -d)
cleanup() { git -C "${ktree}" worktree remove --force "${wt}" 2>/dev/null || rm -rf "${wt}"; }
trap cleanup EXIT
git -C "${ktree}" worktree add -q --detach "${wt}" v7.2.10
git -C "${wt}" -c user.name=verify -c user.email=verify@example.invalid am -q --whitespace=nowarn \
  "${patches}"/*.patch
tree=$(git -C "${wt}" rev-parse 'HEAD^{tree}')
n=$(git -C "${wt}" rev-list --count v7.2.10..HEAD)
echo "commits: ${n}"
echo "tree: ${tree}"
if [[ -n ${expected} && ${tree} != "${expected}" ]]; then
  echo "verify-series.sh: tree differs from ${expected}" >&2
  exit 1
fi
