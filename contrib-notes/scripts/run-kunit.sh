#!/usr/bin/env bash
# Usage: WORK=<dir> run-kunit.sh <name>
# Runs KUnit with surface.kunitconfig in the kernel worktree ${WORK}/kt-<name>.
set -uo pipefail
: "${WORK:?set WORK to the work directory}"
n=$1
here=$(cd "$(dirname "$0")" && pwd)
cd "${WORK}/kt-${n}" || exit 1
rm -rf "${WORK:?}/kbuild-${n}"
./tools/testing/kunit/kunit.py run --arch=x86_64 --jobs=2 \
  --kunitconfig="${here}/surface.kunitconfig" \
  --build_dir="${WORK}/kbuild-${n}" >"${WORK}/kunit-${n}.log" 2>&1
echo "${n} exit=$?" >>"${WORK}/kunit-status.txt"
