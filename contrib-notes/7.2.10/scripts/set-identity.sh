#!/usr/bin/env bash
# Run via `git rebase --exec`: re-commit HEAD with the real kernel identity as committer; for
# commits authored by the placeholder, also set the author and add a Signed-off-by just
# before the final "Patchset:" trailer. The identity comes from KERNEL_NAME and KERNEL_EMAIL
# (the Signed-off-by identity of the fixes' author).
set -euo pipefail
shopt -s inherit_errexit
NAME=${KERNEL_NAME:?set KERNEL_NAME}
EMAIL=${KERNEL_EMAIL:?set KERNEL_EMAIL}
export GIT_COMMITTER_NAME="${NAME}" GIT_COMMITTER_EMAIL="${EMAIL}"
author=$(git log -1 --format=%an)
if [[ ${author} == "PLACEHOLDER-NAME" ]]; then
  msg=$(git log -1 --format=%B)
  sob="Signed-off-by: ${NAME} <${EMAIL}>"
  if ! grep -qxF "${sob}" <<<"${msg}"; then
    msg=$(python3 -I -c '
import sys
m = sys.stdin.read().rstrip("\n").split("\n")
sob = sys.argv[1]
if not m[-1].startswith("Patchset: "):
    sys.exit(f"last line is not a Patchset: trailer: {m[-1]}")
print("\n".join([*m[:-1], sob, m[-1]]))' "${sob}" <<<"${msg}")
  fi
  git commit -q --amend --author="${NAME} <${EMAIL}>" -m "${msg}"
else
  git commit -q --amend --no-edit
fi
