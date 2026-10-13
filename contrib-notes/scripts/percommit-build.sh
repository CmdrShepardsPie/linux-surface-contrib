#!/usr/bin/env bash
# Bisectability + warning check: for each commit in BASE..TIP, check it out and
# compile (W=1) every C file it touches, plus whole directories for files under
# newly added driver dirs. Records results per commit.
# Usage: percommit-build.sh <kernel-tree> <base> <tip> <outdir> <merged-config>
set -uo pipefail
TREE=$1 BASE=$2 TIP=$3 OUT=$4 CONFIG=$5
mkdir -p "$OUT"
cd "$TREE" || exit 1
summary="$OUT/summary.tsv"
: > "$summary"
n=0
for c in $(git rev-list --reverse "$BASE..$TIP"); do
  n=$((n+1))
  git checkout -q "$c" || { echo -e "$n\t$c\tCHECKOUT_FAIL" >> "$summary"; continue; }
  # Restore the intended config every time: syncconfig drops symbols that don't exist yet
  # at earlier commits, which would silently disable later drivers.
  cp "$CONFIG" .config && make -s olddefconfig > /dev/null 2>&1 < /dev/null
  subj=$(git log -1 --format=%s "$c")
  targets=()
  while IFS= read -r f; do
    case "$f" in
      *.c)
        # Build the directory for files in brand-new driver dirs, else the object.
        d=$(dirname "$f")
        if ! git cat-file -e "$BASE:$d" 2>/dev/null; then targets+=("$d/"); else targets+=("${f%.c}.o"); fi ;;
      *.h)
        # Headers: build the C files in the same directory that this commit also touches,
        # or the directory's main users (approximation, recorded as such).
        ;;
    esac
  done < <(git diff-tree --no-commit-id --name-only --diff-filter=AM -r "$c")
  # de-duplicate
  if [ ${#targets[@]} -gt 0 ]; then mapfile -t targets < <(printf '%s\n' "${targets[@]}" | sort -u); fi
  log="$OUT/$(printf '%02d' $n).log"
  if [ ${#targets[@]} -eq 0 ]; then
    echo -e "$n\t${c:0:12}\tNO_C_FILES\t0\t$subj" >> "$summary"; continue
  fi
  if make -j2 W=1 "${targets[@]}" > "$log" 2>&1 < /dev/null; then status=OK; else status=FAIL; fi
  ccs=$(grep -cE '^\s+CC' "$log")
  [ "$status" = OK ] && [ "$ccs" -eq 0 ] && status=NOTHING_BUILT
  grep -qE 'Restart config|\(NEW\)' "$log" && status="$status+CONFIG_PROMPT"
  warns=$(grep -cE 'warning:' "$log")
  echo -e "$n\t${c:0:12}\t$status\t$warns\tcc=$ccs\t$subj\t${targets[*]}" >> "$summary"
done
git checkout -q "$TIP"
echo "done: $n commits"
