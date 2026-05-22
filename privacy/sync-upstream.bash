#!/usr/bin/env bash
# Sync this fork with zed-industries/zed.
#
# What it does:
#   1. Fetches upstream (zed-industries/zed). Tags are intentionally ignored.
#   2. Fast-forwards the local `upstream-main` branch to match `upstream/main`.
#   3. Pushes `upstream-main` to the fork (diegorv/fork-zed) so the fork
#      carries a clean mirror of upstream alongside its `fork` branch.
#   4. Rebases the local `fork` (privacy-mode default branch) onto
#      `upstream/main`, preserving the privacy commit on top.
#   5. Force-pushes the rebased `fork` to the fork repo with `--force-with-lease`.
#
# Remotes expected:
#   origin   -> git@github.com:diegorv/fork-zed.git
#   upstream -> https://github.com/zed-industries/zed.git
#
# Flags:
#   --no-push        Skip every remote push (local sync only).
#   --no-rebase      Skip rebasing `fork`; only update upstream-main.
#   -h, --help       Show this help.

set -euo pipefail

PUSH=1
REBASE=1

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --no-push)   PUSH=0 ;;
        --no-rebase) REBASE=0 ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "Unknown flag: $arg" >&2; usage; exit 2 ;;
    esac
done

cd "$(git rev-parse --show-toplevel)"

require_remote() {
    local name="$1" expected="$2"
    local url
    url=$(git remote get-url "$name" 2>/dev/null || true)
    if [[ -z "$url" ]]; then
        echo "error: remote '$name' is not configured (expected $expected)" >&2
        exit 1
    fi
    if [[ "$url" != *"$expected"* ]]; then
        echo "warning: remote '$name' points to '$url' (expected to contain '$expected')" >&2
    fi
}

require_remote origin   "diegorv/fork-zed"
require_remote upstream "zed-industries/zed"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: working tree has uncommitted changes; commit or stash before syncing" >&2
    exit 1
fi

original_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ -z "$original_branch" ]]; then
    echo "error: HEAD is detached; check out a branch before syncing" >&2
    exit 1
fi

# Defensively neutralize any global fetch settings that would pull tags
# (e.g. `fetch.prunetags = true` in ~/.gitconfig implies `--tags`, which
# overrides the `--no-tags` flag below).
git config --local remote.origin.tagOpt --no-tags
git config --local remote.upstream.tagOpt --no-tags
git config --local fetch.prunetags false

echo "==> Fetching upstream (without tags)"
git fetch upstream --no-tags --prune

echo "==> Updating local 'upstream-main' from 'upstream/main'"
if git show-ref --verify --quiet refs/heads/upstream-main; then
    if [[ "$(git symbolic-ref --short HEAD)" == "upstream-main" ]]; then
        git merge --ff-only upstream/main
    else
        git fetch . upstream/main:upstream-main
    fi
else
    git branch --track upstream-main upstream/main
fi

# Paths the fork fully owns. During rebase, conflicts inside any of
# these paths are resolved by keeping the fork's view (or by re-deleting
# files the fork removed). Trailing slash = directory prefix; otherwise
# exact path match. Files unique to the fork (PRIVACY-MODE.md, privacy/)
# never conflict, but listing them keeps the policy explicit.
FORK_MANAGED_PATHS=(
    ".github/workflows/"
    "README.md"
    "README-UPSTREAM.md"
    "PRIVACY-MODE.md"
    "privacy/"
)

is_fork_managed_path() {
    local file="$1" path
    for path in "${FORK_MANAGED_PATHS[@]}"; do
        if [[ "$path" == */ && "$file" == "$path"* ]]; then
            return 0
        fi
        if [[ "$path" != */ && "$file" == "$path" ]]; then
            return 0
        fi
    done
    return 1
}

# Conflicts within fork-managed paths are resolved by keeping the fork's
# view: files that exist in fork HEAD before the rebase are restored via
# `checkout --ours`, and files that the fork previously deleted are
# re-deleted. Any conflict outside those paths stops the script for
# manual resolution.
rebase_keeping_fork_state() {
    local target="$1"

    local fork_files
    fork_files=$(git ls-tree -r --name-only HEAD 2>/dev/null || true)

    if git rebase "$target"; then
        return 0
    fi

    while [[ -d .git/rebase-merge || -d .git/rebase-apply ]]; do
        local conflicts
        conflicts=$(git status --porcelain | awk '/^(AA|UU|DU|UD|AU|UA|DD)/ {print $2}')

        if [[ -z "$conflicts" ]]; then
            GIT_EDITOR=true git rebase --continue || return 1
            continue
        fi

        local non_managed=""
        while IFS= read -r conflict_file; do
            [[ -z "$conflict_file" ]] && continue
            if ! is_fork_managed_path "$conflict_file"; then
                non_managed+="$conflict_file"$'\n'
            fi
        done <<<"$conflicts"

        if [[ -n "$non_managed" ]]; then
            echo "error: unresolved conflicts outside fork-managed paths:" >&2
            printf '%s' "$non_managed" >&2
            echo "Resolve them manually, then run 'git rebase --continue'." >&2
            return 1
        fi

        while IFS= read -r conflict_file; do
            [[ -z "$conflict_file" ]] && continue
            if echo "$fork_files" | grep -qx "$conflict_file"; then
                echo "  resolving (keep fork's): $conflict_file"
                git checkout --ours -- "$conflict_file"
                git add -- "$conflict_file"
            else
                echo "  resolving (re-delete): $conflict_file"
                git rm -- "$conflict_file" >/dev/null
            fi
        done <<<"$conflicts"

        GIT_EDITOR=true git rebase --continue || continue
    done
}

if [[ "$REBASE" -eq 1 ]]; then
    echo "==> Rebasing 'fork' onto 'upstream/main'"
    if [[ "$original_branch" != "fork" ]]; then
        git checkout fork
    fi
    rebase_keeping_fork_state upstream/main
fi

if [[ "$PUSH" -eq 1 ]]; then
    echo "==> Pushing 'upstream-main' to origin"
    git push origin upstream-main

    if [[ "$REBASE" -eq 1 ]]; then
        echo "==> Force-pushing rebased 'fork' to origin (--force-with-lease)"
        git push --force-with-lease origin fork
    fi
fi

if [[ "$REBASE" -eq 1 && "$original_branch" != "fork" ]]; then
    echo "==> Restoring original branch: $original_branch"
    git checkout "$original_branch"
fi

echo "==> Done"
