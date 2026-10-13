#!/usr/bin/env bash
# Full build of the series' tip with linux-surface's CI config (base + surface + overrides),
# mirroring .github/scripts/autoupdate/build-kernel.sh (make all).
# Usage: KTREE=<kernel tree with the series applied, .config = merged-7.2.10.config>
#        WORK=<output dir> full-build.sh
set -uo pipefail
: "${KTREE:?set KTREE to the kernel tree}" "${WORK:?set WORK to an output directory}"
cd "${KTREE}" || exit 1
export KBUILD_BUILD_HOST=sandbox KBUILD_BUILD_USER=builder
start=$(date +%s)
make -j2 all >"${WORK}/full-build.log" 2>&1 </dev/null
rc=$?
echo "rc=${rc} seconds=$(($(date +%s) - start))" >"${WORK}/full-build.status"
