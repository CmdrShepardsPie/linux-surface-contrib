#!/usr/bin/env bash
# mutate-update-series.sh: check that update-series-tests.sh catches every mutation listed in
# update-series-mutations.txt. Each mutation is applied with sed to a copy of contrib-notes/
# in a temporary directory; a mutation that changes nothing counts as a failure, so the
# list can't go stale silently.
#
# Usage: bash contrib-notes/tests/mutate-update-series.sh
# Exit status: 0 if every mutation applies and is caught.
set -euo pipefail
shopt -s inherit_errexit
unset CDPATH
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)
notes=$(cd -- "${here}/.." >/dev/null && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "${tmp}"' EXIT
n=0 bad=0
while IFS= read -r line; do
  [[ -z ${line} || ${line} == '#'* ]] && continue
  expr=${line%@@*}
  desc=${line##*@@}
  n=$((n + 1))
  rm -rf -- "${tmp:?}/copy"
  mkdir -p "${tmp}/copy"
  cp -r "${notes}" "${tmp}/copy/contrib-notes"
  target=${tmp}/copy/contrib-notes/update-series.sh
  if ! sed -i -e "${expr}" "${target}" || cmp -s "${target}" "${notes}/update-series.sh"; then
    echo "#${n} DID NOT APPLY: ${desc}"
    bad=$((bad + 1))
  elif bash "${tmp}/copy/contrib-notes/tests/update-series-tests.sh" >/dev/null 2>&1; then
    echo "#${n} SURVIVED: ${desc}"
    bad=$((bad + 1))
  else
    echo "#${n} caught: ${desc}"
  fi
done <"${here}/update-series-mutations.txt"
echo
echo "${n} mutations, $((n - bad)) caught."
((bad == 0))
