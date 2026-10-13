#!/usr/bin/env bash
# update-series-tests.sh: hermetic tests for ../update-series.sh, on toy repositories (no
# kernel, no network, nothing outside a temporary directory).
#
# Usage: bash contrib-notes/tests/update-series-tests.sh
#
# The toy "upstream" has the point releases v9.9.1 and v9.9.2 (and, for one test, v9.9.3,
# v9.10.1 and an -rc tag). v9.9.2 makes the change of the series' "fix b" (so that commit
# becomes empty) and changes the line the series' "change c" changes (so that one
# conflicts). The series is written with git format-patch, and a stand-in for
# git-format-patchsets runs git format-patch (one file per commit, not one per patch set).
# Not covered: --percommit and --full (they need a kernel tree).
set -euo pipefail
shopt -s inherit_errexit

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)
script=${here}/../update-series.sh
top=$(mktemp -d)
trap 'rm -rf -- "${top}"' EXIT

# Isolate git from the caller's configuration.
export HOME=${top}/home GIT_CONFIG_NOSYSTEM=1
mkdir -p "${HOME}"
git config --global user.name tester
git config --global user.email tester@example.invalid # privacy-scan: allow (reserved .invalid address)
git config --global init.defaultBranch master
git config --global advice.detachedHead false

# Stand-ins for git-format-patchsets: one that works and one that fails.
mkdir -p "${top}/bin"
cat >"${top}/bin/format-patchsets" <<'EOF'
#!/bin/bash
# Called as: format-patchsets -t --no-confirm RANGE (in the kernel tree's top directory).
exec git format-patch -q "${@: -1}"
EOF
cat >"${top}/bin/format-patchsets-fails" <<'EOF'
#!/bin/bash
echo "format-patchsets: simulated failure" >&2
exit 3
EOF
chmod +x "${top}/bin/format-patchsets" "${top}/bin/format-patchsets-fails"
export GIT_FORMAT_PATCHSETS=${top}/bin/format-patchsets

checks=0 fails=0
current=""
fail() {
  echo "  FAIL [${current}] $*"
  fails=$((fails + 1))
}
ok() { checks=$((checks + 1)); }
expect_rc() {
  ok
  [[ ${rc} -eq $1 ]] || fail "exit status ${rc}, expected $1; output:
${out}"
}
expect_out() {
  ok
  grep -qF -- "$1" <<<"${out}" || fail "output lacks: $1"
}
expect_report() {
  ok
  grep -qxF -- "$1" "${w}/out/report.txt" || fail "report has no line: $1"
}

# commit_file REPO FILE CONTENT SUBJECT: write FILE and commit it.
commit_file() {
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -q -m "$4"
}

# setup: a fresh upstream ($w/up), a series branch's patch files ($w/series), and a clone of
# upstream with its tags as the kernel tree ($w/ks). SERIES names the commits to include.
setup() {
  w=${top}/${current}
  mkdir -p "${w}/up"
  git -C "${w}/up" init -q
  commit_file "${w}/up" a.txt a1 "base: a"
  commit_file "${w}/up" b.txt b1 "base: b"
  commit_file "${w}/up" c.txt "$(printf 'c1\nc2\nc3')" "base: c"
  git -C "${w}/up" tag v9.9.1
  git -C "${w}/up" checkout -q -b series
  local name
  for name in "$@"; do
    case ${name} in
      feature) commit_file "${w}/up" f.txt f1 "add feature" ;;
      fixb) commit_file "${w}/up" b.txt b2 "fix b" ;;
      changec) commit_file "${w}/up" c.txt "$(printf 'c1\ncY\nc3')" "change c" ;;
      dropme) commit_file "${w}/up" d.txt d1 "drop me" ;;
      *) echo "setup: unknown commit ${name}" >&2; exit 2 ;;
    esac
  done
  mkdir -p "${w}/series"
  git -C "${w}/up" format-patch -q -o "${w}/series" v9.9.1..series
  git -C "${w}/up" checkout -q master
  git -C "${w}/up" branch -q -D series
  commit_file "${w}/up" b.txt b2 "stable: fix b"
  commit_file "${w}/up" c.txt "$(printf 'c1\ncX\nc3')" "stable: change c"
  git -C "${w}/up" tag v9.9.2
  git clone -q "${w}/up" "${w}/ks"
}

run() {
  rc=0
  out=$(bash "${script}" "$@" 2>&1) || rc=$?
}

# --- the tests ---------------------------------------------------------------------------

t_empty_and_dropped_commits() {
  setup feature fixb dropme
  run --out "${w}/out" --drop "drop me" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  expect_rc 0
  expect_report "from: v9.9.1 (3 commits)"
  expect_report "to: v9.9.2 (1 commits)"
  expect_report "already in v9.9.2 (left out):"
  expect_report "  fix b"
  expect_report "dropped with --drop:"
  expect_report "  drop me"
  expect_report "patch files: 1"
  # The regenerated patch file applies to v9.9.2 and adds the feature, nothing else.
  ok
  git -C "${w}/ks" checkout -q --detach v9.9.2
  git -C "${w}/ks" am -q "${w}/out/patches"/*.patch || fail "patch files don't apply to v9.9.2"
  [[ $(<"${w}/ks/f.txt") == f1 && ! -e ${w}/ks/d.txt ]] || fail "wrong tree after git am"
}

t_conflict_then_continue() {
  setup feature changec
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  expect_rc 1
  expect_out 'update-series.sh: conflict in "change c". Resolve it in'
  expect_out "update-series.sh --continue ${w}/ks ${w}/out"
  printf 'c1\ncZ\nc3\n' >"${w}/out/kernel/c.txt"
  git -C "${w}/out/kernel" add c.txt
  run --continue "${w}/ks" "${w}/out"
  expect_rc 0
  expect_report "conflicts resolved by hand:"
  expect_report "  change c"
  expect_report "to: v9.9.2 (2 commits)"
  ok
  local line2
  line2=$(sed -n 2p "${w}/out/kernel/c.txt")
  [[ ${line2} == cZ ]] || fail "the resolution isn't in the result"
}

# A hand resolution that leaves nothing to commit: recorded as already in the release.
t_conflict_resolved_to_nothing() {
  setup changec
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  expect_rc 1
  git -C "${w}/out/kernel" checkout -q --ours c.txt
  git -C "${w}/out/kernel" add c.txt
  run --continue "${w}/ks" "${w}/out"
  expect_rc 0
  expect_report "already in v9.9.2 (left out):"
  expect_report "  change c"
  expect_report "to: v9.9.2 (0 commits)"
  expect_report "patch files: 0"
}

t_continue_refuses_unresolved() {
  setup changec
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  run --continue "${w}/ks" "${w}/out"
  expect_rc 1
  expect_out "aren't resolved yet; git add the files first"
}

t_refuses_wrong_base() {
  setup changec
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.2
  expect_rc 1
  expect_out "doesn't apply to v9.9.2; give the release it's based on"
  # The temporary worktree is gone.
  ok
  local trees
  trees=$(git -C "${w}/ks" worktree list --porcelain | grep -c '^worktree ')
  [[ ${trees} -eq 1 ]] || fail "a worktree was left behind"
}

t_refuses_dirty_tree() {
  setup feature
  echo changed >"${w}/ks/a.txt"
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  expect_rc 1
  expect_out "has local changes"
}

t_refuses_stray_patch_files() {
  setup feature
  touch "${w}/ks/old.patch"
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  expect_rc 1
  expect_out "has *.patch files in its top directory (old.patch); move them away first"
  # Refused before anything was set up.
  ok
  [[ ! -e ${w}/out/worktree ]] || fail "the run started before refusing"
}

t_refuses_used_out_dir() {
  setup feature
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  expect_rc 1
  expect_out "already holds a run; use another --out or --continue"
}

t_refuses_bad_from_tag() {
  setup feature
  run --out "${w}/out" "${w}/ks" "${w}/series" 9.9.1
  expect_rc 1
  expect_out "FROM_TAG must look like v6.18.18"
}

# Without TO_TAG: the newest vX.Y.N on origin, not another series and not an -rc.
t_default_target_is_newest_point_release() {
  setup feature
  commit_file "${w}/up" e.txt e1 "stable: e"
  git -C "${w}/up" tag v9.9.3
  git -C "${w}/up" tag v9.9.4-rc1
  git -C "${w}/up" tag v9.10.1
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1
  expect_rc 0
  expect_report "to: v9.9.3 (1 commits)"
}

# A missing tag is fetched in full: the user's clone must not become shallow.
t_fetches_missing_tag_without_shallowing() {
  setup feature
  git -C "${w}/ks" tag -d v9.9.2 >/dev/null
  run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  expect_rc 0
  ok
  git -C "${w}/ks" rev-parse -q --verify refs/tags/v9.9.2 >/dev/null || fail "v9.9.2 wasn't fetched"
  ok
  [[ ! -e ${w}/ks/.git/shallow ]] || fail "the clone was made shallow"
}

# When git-format-patchsets fails, the kernel tree is put back on its branch, without
# stray patch files, and --continue finishes once the tool works.
t_tool_failure_restores_checkout() {
  setup feature
  GIT_FORMAT_PATCHSETS=${top}/bin/format-patchsets-fails run --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2
  expect_rc 1
  expect_out "is back on master. Re-run with --continue once it's fixed."
  ok
  local branch
  branch=$(git -C "${w}/ks" symbolic-ref -q --short HEAD) || branch=""
  [[ ${branch} == master ]] || fail "the kernel tree isn't back on master"
  run --continue "${w}/ks" "${w}/out"
  expect_rc 0
  expect_report "patch files: 1"
}

# With CDPATH set, a relative cd may resolve to another directory (and prints it). Called by a
# relative path, with a decoy contrib-notes/ on CDPATH, the script must still find its own
# helpers.
t_works_with_cdpath() {
  setup feature
  mkdir -p "${w}/cdpath/contrib-notes"
  rc=0
  out=$(cd -- "${here}/../.." >/dev/null && CDPATH=${w}/cdpath bash contrib-notes/update-series.sh \
    --out "${w}/out" "${w}/ks" "${w}/series" v9.9.1 v9.9.2 2>&1) || rc=$?
  expect_rc 0
  expect_report "to: v9.9.2 (1 commits)"
}

# --- runner ------------------------------------------------------------------------------

fns=$(declare -F | awk '$3 ~ /^t_/ {print $3}')
n=0
for current in ${fns}; do
  before=${fails}
  "${current}"
  n=$((n + 1))
  if ((fails == before)); then echo "ok     ${current}"; else echo "not ok ${current}"; fi
done
echo
echo "${n} tests, ${checks} checks, ${fails} failed."
((fails == 0))
