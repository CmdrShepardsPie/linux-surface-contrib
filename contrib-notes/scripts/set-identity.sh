#!/usr/bin/env bash
# Run via `git rebase --exec`: re-commit HEAD with the real kernel identity as
# committer; for commits authored by the placeholder, also set the author and add
# a Signed-off-by just before the final "Patchset:" trailer.
set -euo pipefail
# The identity comes from KERNEL_NAME and KERNEL_EMAIL (the owner's Signed-off-by identity).
NAME=${KERNEL_NAME:?set KERNEL_NAME} EMAIL=${KERNEL_EMAIL:?set KERNEL_EMAIL}
export GIT_COMMITTER_NAME="$NAME" GIT_COMMITTER_EMAIL="$EMAIL"
if [ "$(git log -1 --format=%an)" = "PLACEHOLDER-NAME" ]; then
  msg=$(git log -1 --format=%B)
  sob="Signed-off-by: $NAME <$EMAIL>"
  if ! grep -qxF "$sob" <<<"$msg"; then
    msg=$(python3 -c '
import sys
m=sys.stdin.read().rstrip("\n").split("\n"); sob=sys.argv[1]
assert m[-1].startswith("Patchset: "), m[-1]
print("\n".join(m[:-1]+[sob, m[-1]]))' "$sob" <<<"$msg")
  fi
  git commit -q --amend --author="$NAME <$EMAIL>" -m "$msg"
else
  git commit -q --amend --no-edit
fi
