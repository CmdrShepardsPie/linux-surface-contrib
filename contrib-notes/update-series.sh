#!/usr/bin/env bash
# update-series.sh: move one of linux-surface's patch sets (patches/<series>) to a newer
# point release, in one run. Mirrors linux-surface's own autoupdate (rebase-kernel.sh,
# generate-patches.sh, build-kernel.sh), but starts from the patch files in a branch of this
# repository rather than from a branch of linux-surface/kernel, and runs locally.
#
# Usage:
#   update-series.sh [options] KERNEL_TREE PATCH_DIR FROM_TAG [TO_TAG]
#   update-series.sh --continue KERNEL_TREE OUT_DIR
#
#   KERNEL_TREE  a clone of https://github.com/linux-surface/kernel (or any tree with the
#                stable tags), with no local changes; FROM_TAG and TO_TAG are fetched into
#                it if missing
#   PATCH_DIR    the patch set to update, e.g. patches/6.18 of this branch
#   FROM_TAG     the release PATCH_DIR applies to (e.g. v6.18.18); checked by applying it
#   TO_TAG       the target release; default: the newest vX.Y.Z tag on the kernel tree's
#                origin for FROM_TAG's X.Y (never an -rc)
#
# Options:
#   --out DIR      where to write the result (default: ./update-<TO_TAG>)
#   --drop SUBJ    leave out the commit with this exact subject (repeatable), for patches
#                  that stable has superseded in another form; say why in the branch notes
#   --percommit CONFIG  after regenerating, build every commit's touched C files with W=1
#                  (percommit-build.sh) using CONFIG, a merged linux-surface CI config
#   --full CONFIG  after that, a full "make all" of the tip with CONFIG (full-build.sh)
#
# What it writes to OUT_DIR:
#   patches/      the regenerated patch files (git-format-patchsets -t, as upstream does);
#                 copy them over PATCH_DIR
#   report.txt    FROM/TO, commit counts, the tree ID, commits that became empty (already in
#                 stable) or were dropped, and each commit that needed a conflict resolved
#   range-diff.txt  git range-diff of the old series against the new one
#   worktree      (a path) the kernel worktree with the result, kept for builds and review
#
# On a conflict it stops and prints what to do: resolve it in the worktree (follow how the
# newer series, such as patches/7.2, solved the same conflict where it has one), "git add"
# the files, then run "update-series.sh --continue KERNEL_TREE OUT_DIR". Commits get a fixed
# committer and date, so the "From <id>" lines in the patch files are the same on every run.
#
# If a hand resolution leaves a commit with no changes (the target release already has
# it), --continue records it as already in the release, like any other empty commit.
#
# Needs: git, git-format-patchsets (https://github.com/qzed/git-tools; GIT_FORMAT_PATCHSETS
# names it), and for --percommit/--full the kernel build dependencies. The verification and
# build helpers are taken from this directory: verify-series.sh,
# 7.2.10/scripts/percommit-build.sh and 7.2.10/scripts/full-build.sh.
#
# Tests: tests/update-series-tests.sh (a toy repository; no kernel needed), and
# tests/mutate-update-series.sh, which checks that they catch every mutation in
# tests/update-series-mutations.txt. Not covered: --percommit and --full (they need a
# kernel tree), and the real git-format-patchsets (the tests stand in git format-patch,
# which writes one file per commit).
set -euo pipefail
shopt -s inherit_errexit

# Paths are taken as given: with CDPATH set, cd could resolve a relative path through it to
# another directory (and prints the one it chose).
unset CDPATH
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)
tool=${GIT_FORMAT_PATCHSETS:-git-format-patchsets}
# A placeholder committer for the rebuilt commits, as in genpatchsets.sh.
id_email=builder@example.invalid # privacy-scan: allow (reserved .invalid address, no person)
export GIT_COMMITTER_NAME=builder GIT_COMMITTER_EMAIL=${id_email}
export GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

die() {
  echo "update-series.sh: $*" >&2
  exit 1
}
usage() { sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p}' "${BASH_SOURCE[0]}"; }

out="" percommit="" full="" cont=0
drops=()
while (($#)); do
  case $1 in
    --out) out=$2; shift 2 ;;
    --drop) drops+=("$2"); shift 2 ;;
    --percommit) percommit=$2; shift 2 ;;
    --full) full=$2; shift 2 ;;
    --continue) cont=1; shift ;;
    -h | --help) usage; exit 0 ;;
    --*) die "unknown option: $1 (see --help)" ;;
    *) break ;;
  esac
done

# no_stray_patches KS: git-format-patchsets writes into KS's top directory, and every
# *.patch there is collected afterwards, so there must be none beforehand.
no_stray_patches() {
  local stray
  stray=$(find "$1" -maxdepth 1 -name '*.patch' -print -quit)
  [[ -z ${stray} ]] || die "$1 has *.patch files in its top directory (${stray##*/}); move them away first"
}

# finish: regenerate the patch files from the worktree, verify them, write the report, build.
finish() {
  local wt=$1 dir=$2 from to old_tip n tree
  from=$(<"${dir}/.from")
  to=$(<"${dir}/.to")
  old_tip=$(<"${dir}/.old-tip")
  n=$(git -C "${wt}" rev-list --count "${to}..HEAD")
  tree=$(git -C "${wt}" rev-parse 'HEAD^{tree}')
  rm -rf "${dir:?}/patches"
  mkdir -p "${dir}/patches"
  # git-format-patchsets writes into the current directory and expects .git to be a
  # directory, so run it in the main tree on a detached copy of the result.
  local ks tip orig
  ks=$(<"${dir}/.kernel-tree")
  tip=$(git -C "${wt}" rev-parse HEAD)
  orig=$(git -C "${ks}" symbolic-ref -q --short HEAD || git -C "${ks}" rev-parse HEAD)
  # Nothing left (every commit is in the release already): no patch files to write.
  if ((n > 0)); then
    no_stray_patches "${ks}"
    git -C "${ks}" checkout -q --detach "${tip}"
    # A fixed abbreviation length for the "index" lines: git otherwise lengthens them as the
    # clone holds more objects, so the same series would give different files in a deeper
    # clone.
    if ! (cd -- "${ks}" >/dev/null &&
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.abbrev GIT_CONFIG_VALUE_0=12 EDITOR=true \
        "${tool}" -t --no-confirm "${to}..HEAD" >/dev/null &&
      mv ./*.patch "${dir}/patches/"); then
      rm -f -- "${ks}"/*.patch
      git -C "${ks}" checkout -q "${orig}"
      die "${tool} failed; ${ks} is back on ${orig}. Re-run with --continue once it's fixed."
    fi
    git -C "${ks}" checkout -q "${orig}"
    bash "${here}/verify-series.sh" "${ks}" "${to}" "${dir}/patches" "${tree}" >/dev/null ||
      die "the regenerated patch files don't reproduce the tree ${tree}"
  fi
  git -C "${ks}" range-diff --no-color "${from}..${old_tip}" "${to}..${tip}" >"${dir}/range-diff.txt" || true
  local n_old n_files
  n_old=$(git -C "${ks}" rev-list --count "${from}..${old_tip}")
  n_files=$(find "${dir}/patches" -maxdepth 1 -name '*.patch' | wc -l)
  {
    echo "from: ${from} (${n_old} commits)"
    echo "to: ${to} (${n} commits)"
    echo "tree: ${tree}"
    echo "patch files: ${n_files}"
    if [[ -s ${dir}/.empty ]]; then echo "already in ${to} (left out):"; sed 's/^/  /' "${dir}/.empty"; fi
    if [[ -s ${dir}/.dropped ]]; then echo "dropped with --drop:"; sed 's/^/  /' "${dir}/.dropped"; fi
    if [[ -s ${dir}/.resolved ]]; then echo "conflicts resolved by hand:"; sed 's/^/  /' "${dir}/.resolved"; fi
  } >"${dir}/report.txt"
  cat "${dir}/report.txt"
  if [[ -n $(<"${dir}/.percommit") ]]; then
    bash "${here}/7.2.10/scripts/percommit-build.sh" "${wt}" "${to}" "${tip}" \
      "${dir}/percommit" "$(<"${dir}/.percommit")"
    git -C "${wt}" checkout -q --detach "${tip}"
    echo "per-commit build: ${dir}/percommit/summary.tsv"
  fi
  if [[ -n $(<"${dir}/.full") ]]; then
    cp "$(<"${dir}/.full")" "${wt}/.config"
    make -C "${wt}" -s olddefconfig </dev/null
    KTREE=${wt} WORK=${dir} bash "${here}/7.2.10/scripts/full-build.sh"
    echo "full build: $(<"${dir}/full-build.status")"
  fi
}

# pick: cherry-pick the remaining commits listed in DIR/.todo onto the worktree, one by one.
pick() {
  local wt=$1 dir=$2 c subj d skip changed
  while [[ -s ${dir}/.todo ]]; do
    c=$(head -n 1 "${dir}/.todo")
    subj=$(git -C "${wt}" log -1 --format=%s "${c}")
    skip=0
    for d in "${drops[@]}"; do [[ ${subj} == "${d}" ]] && skip=1; done
    if ((skip)); then
      echo "${subj}" >>"${dir}/.dropped"
    elif ! git -C "${wt}" cherry-pick --allow-empty --keep-redundant-commits "${c}" >/dev/null 2>&1; then
      echo "${subj}" >"${dir}/.conflict"
      git -C "${wt}" status --short | grep -E '^(UU|AA|DU|UD) ' >&2 || true
      die "conflict in \"${subj}\". Resolve it in ${wt}, git add the files, then run:
  update-series.sh --continue $(<"${dir}/.kernel-tree") ${dir}"
    else
      changed=$(git -C "${wt}" diff-tree --no-commit-id --name-only -r HEAD)
      if [[ -z ${changed} ]]; then
        git -C "${wt}" reset -q --hard HEAD~1
        echo "${subj}" >>"${dir}/.empty"
      fi
    fi
    sed -i 1d "${dir}/.todo"
  done
}

if ((cont)); then
  (($# == 2)) || die "usage: update-series.sh --continue KERNEL_TREE OUT_DIR"
  dir=$(cd -- "$2" >/dev/null && pwd)
  [[ -s ${dir}/worktree ]] || die "${dir} holds no run to continue"
  wt=$(<"${dir}/worktree")
  mapfile -t drops <"${dir}/.drops"
  if [[ -s ${dir}/.conflict ]]; then
    unmerged=$(git -C "${wt}" ls-files -u)
    [[ -z ${unmerged} ]] || die "conflicts in ${wt} aren't resolved yet; git add the files first"
    if git -C "${wt}" diff --cached --quiet; then
      # The resolution left nothing to commit: the release already has this change.
      git -C "${wt}" cherry-pick --skip >/dev/null
      cat "${dir}/.conflict" >>"${dir}/.empty"
    else
      git -C "${wt}" -c core.editor=true cherry-pick --continue >/dev/null ||
        die "git cherry-pick --continue failed in ${wt}"
      cat "${dir}/.conflict" >>"${dir}/.resolved"
    fi
    rm -f "${dir}/.conflict"
    sed -i 1d "${dir}/.todo"
  fi
  pick "${wt}" "${dir}"
  finish "${wt}" "${dir}"
  exit 0
fi

(($# == 3 || $# == 4)) || die "usage: update-series.sh [options] KERNEL_TREE PATCH_DIR FROM_TAG [TO_TAG] (see --help)"
ks=$(cd -- "$1" >/dev/null && pwd)
patches=$(cd -- "$2" >/dev/null && pwd)
from=$3
to=${4:-}
[[ ${from} =~ ^v([0-9]+\.[0-9]+)\.[0-9]+$ ]] || die "FROM_TAG must look like v6.18.18"
series=${BASH_REMATCH[1]}
dirty=$(git -C "${ks}" status --porcelain --untracked-files=no)
[[ -z ${dirty} ]] || die "${ks} has local changes"
no_stray_patches "${ks}"
if [[ -z ${to} ]]; then
  tags=$(git -C "${ks}" ls-remote --tags --refs origin "refs/tags/v${series}.*")
  to=$(sed -n 's|.*refs/tags/||p' <<<"${tags}" | grep -E "^v${series//./\\.}\.[0-9]+$" | sort -V | tail -n 1)
  [[ -n ${to} ]] || die "no v${series}.N tag found on ${ks}'s origin"
fi
[[ ${to} =~ ^v${series//./\\.}\.[0-9]+$ ]] || die "TO_TAG ${to} isn't a ${series} point release"
for t in "${from}" "${to}"; do
  if ! git -C "${ks}" rev-parse -q --verify "refs/tags/${t}" >/dev/null; then
    # A full fetch: --depth would make the user's clone shallow.
    git -C "${ks}" fetch -q origin "refs/tags/${t}:refs/tags/${t}" || die "can't fetch ${t} from ${ks}'s origin"
  fi
done
out=${out:-./update-${to}}
mkdir -p "${out}"
dir=$(cd -- "${out}" >/dev/null && pwd)
[[ ! -e ${dir}/worktree ]] || die "${dir} already holds a run; use another --out or --continue"

# The old series, applied to FROM_TAG: this checks that PATCH_DIR really is based there.
old=${dir}/old
git -C "${ks}" worktree add -q --detach "${old}" "${from}"
if ! git -C "${old}" am -q --whitespace=nowarn "${patches}"/*.patch >/dev/null 2>&1; then
  git -C "${old}" am --abort >/dev/null 2>&1 || true
  git -C "${ks}" worktree remove --force "${old}"
  die "${patches} doesn't apply to ${from}; give the release it's based on"
fi
old_tip=$(git -C "${old}" rev-parse HEAD)
# Keep the old series reachable (for the range-diff) after its worktree goes.
git -C "${ks}" update-ref "refs/update-series/${from}" "${old_tip}"
git -C "${ks}" worktree remove --force "${old}"
n_old=$(git -C "${ks}" rev-list --count "${from}..${old_tip}")
echo "old series: ${n_old} commits on ${from}"

wt=${dir}/kernel
git -C "${ks}" worktree add -q --detach "${wt}" "${to}"
printf '%s\n' "${wt}" >"${dir}/worktree"
printf '%s\n' "${ks}" >"${dir}/.kernel-tree"
printf '%s\n' "${from}" >"${dir}/.from"
printf '%s\n' "${to}" >"${dir}/.to"
printf '%s\n' "${old_tip}" >"${dir}/.old-tip"
printf '%s\n' "${percommit}" >"${dir}/.percommit"
printf '%s\n' "${full}" >"${dir}/.full"
if ((${#drops[@]})); then printf '%s\n' "${drops[@]}" >"${dir}/.drops"; else : >"${dir}/.drops"; fi
: >"${dir}/.empty"
: >"${dir}/.dropped"
: >"${dir}/.resolved"
git -C "${ks}" rev-list --reverse "${from}..${old_tip}" >"${dir}/.todo"
pick "${wt}" "${dir}"
finish "${wt}" "${dir}"
