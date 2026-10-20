#!/usr/bin/env bash
# Runs git-trim against throwaway repos. Interactive cases drive gum through a pty with
# script(1), sending keystrokes with pauses so each prompt has rendered before input lands.
set -euo pipefail

GT="$(cd "$(dirname "$0")/.." && pwd)/git-trim"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export TERM=xterm-256color GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

ENTER=$'\r'
TAB=$'\t'
ESC=$'\e'
passed=0
failed=0

# Fixture
branch() {
  git checkout -q -b "$1" main
  echo "$1" >"${1//\//_}"
  git add -A
  git commit -q -m "work on $1, with a comma"
  git checkout -q main
}

fixture() {
  # sq: squash-merged, upstream gone; merged-br: merged, upstream kept;
  # gone-unmerged: upstream gone with 1 unique commit; never-pushed: local only;
  # wt-gone: squash-merged but checked out in a worktree; feature: current branch.
  local dir="$ROOT/$1"
  git init -q -b main --bare "$dir/remote.git"
  git clone -q "$dir/remote.git" "$dir/w" 2>/dev/null
  cd "$dir/w"
  git commit -q --allow-empty -m init
  git push -q origin main
  git remote set-head origin main

  branch sq
  git push -q -u origin sq
  git merge -q --squash sq >/dev/null
  git commit -q -m "squash sq"
  git push -q origin main
  git push -q origin --delete sq

  branch merged-br
  git push -q -u origin merged-br
  git merge -q --no-ff -m "merge merged-br" merged-br
  git push -q origin main

  branch gone-unmerged
  git push -q -u origin gone-unmerged
  git push -q origin --delete gone-unmerged

  branch never-pushed

  branch wt-gone
  git push -q -u origin wt-gone
  git merge -q --squash wt-gone >/dev/null
  git commit -q -m "squash wt-gone"
  git push -q origin main
  git push -q origin --delete wt-gone
  git worktree add -q "$dir/wt" wt-gone

  branch feature
  git checkout -q feature
}

# Running
drive() {
  # drive "<key> <key> ..." args...: each key is sent ~1s apart into a pty running git-trim.
  local keys="$1" key
  shift
  {
    # Keys sent while the fetch spinner runs are swallowed, so wait for the picker first.
    sleep 2
    for key in $keys; do
      sleep 1.2
      case "$key" in
        enter) printf '%s' "$ENTER" ;;
        tab) printf '%s' "$TAB" ;;
        esc) printf '%s' "$ESC" ;;
        *) printf '%s' "$key" ;;
      esac
    done
    sleep 1.5
  } | script -qec "$(printf '%q ' "$GT" "$@")" /dev/null >"$ROOT/raw" 2>&1 || true
  # Strip colours and cursor control so assertions see plain text.
  sed 's/\x1b\[[0-9;?<>]*[a-zA-Z]//g; s/\x1b\][^\a]*\a//g' "$ROOT/raw" | tr '\r' '\n' >"$ROOT/out"
}

has_branch() {
  git show-ref --verify --quiet "refs/heads/$1"
}

remote_has() {
  git ls-remote --exit-code --heads origin "$1" >/dev/null
}

check() {
  local name="$1"
  shift
  if "$@"; then
    passed=$((passed + 1))
    printf '  ok    %s\n' "$name"
  else
    failed=$((failed + 1))
    printf '  FAIL  %s\n' "$name"
  fi
}

not() {
  ! "$@"
}

output_has() {
  grep -q -- "$1" "$ROOT/out"
}

# Cases
echo "dry run, default categories"
fixture dry
"$GT" --dry-run >"$ROOT/out" 2>&1
check "lists squash-merged branch with gone upstream" output_has "gone · squash-merged"
check "lists merged branch" output_has "merged-br"
check "lists gone branch with its at-risk commit" output_has "1 commit(s)"
check "never offers main from a feature branch" not grep -q "│ main " "$ROOT/out"
check "never offers the current branch" not grep -q "│ feature " "$ROOT/out"
check "leaves local-only branches out of the default" not output_has "never-pushed"
check "skips worktree branches with a note" output_has "worktree: wt-gone"

echo "combined categories"
"$GT" --merged --squashed --dry-run >"$ROOT/out" 2>&1
check "runs every requested category" bash -c "grep -q merged-br '$ROOT/out' && grep -q 'squash-merged' '$ROOT/out'"

echo "squash detection outside --squashed"
"$GT" --pruned --dry-run >"$ROOT/out" 2>&1
check "--pruned does not flag a squash-merged branch as at risk" bash -c "grep '│ sq ' '$ROOT/out' | grep -q '│ -  '"

echo "refuses without a terminal"
check "exits non-zero" not "$GT" </dev/null >"$ROOT/out" 2>&1
check "says why" output_has "needs a terminal"
check "deletes nothing" has_branch merged-br

echo "picker then Enter on the confirmation"
drive "enter enter"
check "Enter alone cancels" has_branch merged-br
check "shows the final table" output_has "About to delete"

echo "picker then y"
drive "enter y"
check "deletes pre-selected merged branch" not has_branch merged-br
check "deletes pre-selected squash-merged branch" not has_branch sq
check "keeps at-risk branch it did not pre-select" has_branch gone-unmerged
check "logs the sha for recovery" output_has "was="

echo "Esc in the picker"
fixture esc
drive "esc"
check "cancels without deleting" has_branch merged-br

echo "at-risk branch needs its own confirmation"
fixture risk
drive "tab enter n y"
check "declining the at-risk prompt keeps it" has_branch gone-unmerged
check "the rest still go" not has_branch merged-br
fixture risk2
drive "tab enter y y"
check "accepting both deletes it" not has_branch gone-unmerged

echo "--remote"
fixture remote
branch remote-merged
git push -q origin remote-merged
git merge -q --no-ff -m "merge remote-merged" remote-merged
git push -q origin main
git checkout -q feature
drive "enter y" --remote
check "deletes the merged remote branch" not remote_has remote-merged
check "never deletes the default branch" remote_has main
check "rejects --remote with --pruned" not "$GT" --remote --pruned --dry-run 2>/dev/null

echo "--reset uses the named remote"
fixture reset
git init -q --bare "$ROOT/reset/other.git"
git remote add other "$ROOT/reset/other.git"
git push -q other main never-pushed
"$GT" --reset=other --dry-run >"$ROOT/out" 2>&1
check "keeps a branch that exists on that remote" not output_has "never-pushed"
check "lists one that does not" output_has "not on other"

echo "--tracked never touches a protected upstream"
fixture tracked
git checkout -q -b follows-main --track origin/main
git checkout -q feature
"$GT" --all --tracked --dry-run >"$ROOT/out" 2>&1
check "only deletes the local branch" bash -c "grep follows-main '$ROOT/out' | grep -q 'delete local ' && ! grep follows-main '$ROOT/out' | grep -q 'origin/main'"

echo "fetch failure"
fixture fetch
git remote set-url origin "$ROOT/missing.git"
check "stops instead of using stale data" not "$GT" --dry-run >"$ROOT/out" 2>&1
check "says fetch failed" output_has "Fetch failed"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
