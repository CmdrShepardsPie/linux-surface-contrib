#!/usr/bin/env bash
# Bisectability and warning check: for each commit in BASE..TIP, check it out and compile
# (W=1) every C file it touches, or the whole directory for files in a directory the series
# adds. Records one line per commit in OUTDIR/summary.tsv and the build log in OUTDIR/NN.log.
# Usage: percommit-build.sh <kernel-tree> <base> <tip> <outdir> <merged-config>
# Headers aren't built on their own; the full build (full-build.sh) covers them.
set -uo pipefail
shopt -s inherit_errexit
usage="usage: percommit-build.sh KERNEL_TREE BASE TIP OUTDIR CONFIG"
TREE=${1:?${usage}}
BASE=${2:?${usage}}
TIP=${3:?${usage}}
OUT=${4:?${usage}}
CONFIG=${5:?${usage}}
mkdir -p "${OUT}"
OUT=$(cd "${OUT}" && pwd)
config_dir=$(dirname "${CONFIG}")
config_dir=$(cd "${config_dir}" && pwd) || exit 1
CONFIG=${config_dir}/${CONFIG##*/}
cd "${TREE}" || exit 1
summary=${OUT}/summary.tsv
: >"${summary}"
revs=$(git rev-list --reverse "${BASE}..${TIP}") || exit 1
n=0
for c in ${revs}; do
  n=$((n + 1))
  if ! git checkout -q "${c}"; then
    printf '%s\t%s\tCHECKOUT_FAIL\n' "${n}" "${c}" >>"${summary}"
    continue
  fi
  # Restore the intended config every time: syncconfig drops symbols that don't exist yet
  # at earlier commits, which would silently disable later drivers.
  cp "${CONFIG}" .config && make -s olddefconfig >/dev/null 2>&1 </dev/null
  subj=$(git log -1 --format=%s "${c}")
  changed=$(git diff-tree --no-commit-id --name-only --diff-filter=AM -r "${c}")
  targets=()
  while IFS= read -r f; do
    case ${f} in
      *.c)
        # The whole directory for files in a directory the series adds, else the object.
        d=$(dirname "${f}")
        if git cat-file -e "${BASE}:${d}" 2>/dev/null; then
          targets+=("${f%.c}.o")
        else
          targets+=("${d}/")
        fi
        ;;
      *) ;;
    esac
  done <<<"${changed}"
  if ((${#targets[@]} > 0)); then
    sorted=$(printf '%s\n' "${targets[@]}" | sort -u)
    mapfile -t targets <<<"${sorted}"
  fi
  log=$(printf '%s/%02d.log' "${OUT}" "${n}")
  if ((${#targets[@]} == 0)); then
    printf '%s\t%s\tNO_C_FILES\t0\t%s\n' "${n}" "${c:0:12}" "${subj}" >>"${summary}"
    continue
  fi
  if make -j2 W=1 "${targets[@]}" >"${log}" 2>&1 </dev/null; then status=OK; else status=FAIL; fi
  ccs=$(grep -cE '^\s+CC' "${log}") || ccs=0
  if [[ ${status} == OK && ${ccs} -eq 0 ]]; then status=NOTHING_BUILT; fi
  if grep -qE 'Restart config|\(NEW\)' "${log}"; then status="${status}+CONFIG_PROMPT"; fi
  warns=$(grep -cE 'warning:' "${log}") || warns=0
  printf '%s\t%s\t%s\t%s\tcc=%s\t%s\t%s\n' "${n}" "${c:0:12}" "${status}" "${warns}" "${ccs}" \
    "${subj}" "${targets[*]}" >>"${summary}"
done
git checkout -q "${TIP}"
echo "done: ${n} commits"
