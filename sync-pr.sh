#!/usr/bin/env bash
set -euo pipefail

REMOTE="origin"
SUCCEEDED=false
STASHED=false
ORIGINAL_BRANCH=""
FEATURE=""
MAIN=""
REBASE_CONFLICT=false
PUSH=false

usage() {
  cat <<'EOF'
Usage:
  sync-pr [--push] <main>                  Rebase current branch onto origin/<main>
  sync-pr [--push] <feature> <main>        Rebase <feature> onto origin/<main>

Examples:
  sync-pr main
  sync-pr --push main
  sync-pr feature/wallet-refactor main
EOF
}

log() {
  echo "$@"
}

error() {
  echo "error: $*" >&2
}

branch_exists_locally() {
  git show-ref --verify --quiet "refs/heads/$1"
}

branch_exists_on_remote() {
  git show-ref --verify --quiet "refs/remotes/${REMOTE}/$1"
}

is_rebase_in_progress() {
  [[ -d .git/rebase-merge || -d .git/rebase-apply ]]
}

is_worktree_dirty() {
  ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]
}

restore_state() {
  if [[ "$SUCCEEDED" == true ]]; then
    return 0
  fi

  if is_rebase_in_progress; then
    git rebase --abort >/dev/null 2>&1 || true
  fi

  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null || true)"
  if [[ -n "$ORIGINAL_BRANCH" && "$current_branch" != "$ORIGINAL_BRANCH" ]]; then
    git checkout "$ORIGINAL_BRANCH" >/dev/null 2>&1 || true
  fi

  if [[ "$STASHED" == true ]]; then
    git stash pop >/dev/null 2>&1 || true
  fi
}

on_exit() {
  local exit_code=$?

  if [[ "$SUCCEEDED" == true ]]; then
    return 0
  fi

  restore_state

  if [[ "$REBASE_CONFLICT" == true ]]; then
    error "Rebase aborted due to conflicts. Your repo has been restored to its pre-sync state."
    error "Resolve conflicts manually with:"
    error "  git fetch ${REMOTE} ${MAIN}"
    error "  git checkout ${FEATURE}"
    error "  git rebase ${REMOTE}/${MAIN}"
    error "Then fix conflicts and run: git rebase --continue"
  elif [[ $exit_code -ne 0 ]]; then
    error "sync-pr failed. Your repo has been restored to its pre-sync state."
  fi

  return "$exit_code"
}

parse_args() {
  local args=()
  for arg in "$@"; do
    case "$arg" in
      --push) PUSH=true ;;
      -*) error "unknown option: $arg"; usage >&2; exit 1 ;;
      *) args+=("$arg") ;;
    esac
  done

  if [[ ${#args[@]} -eq 0 || ${#args[@]} -gt 2 ]]; then
    usage >&2
    exit 1
  fi

  if [[ ${#args[@]} -eq 1 ]]; then
    MAIN="${args[0]}"
    FEATURE="$(git branch --show-current)"
    if [[ -z "$FEATURE" ]]; then
      error "not on a branch; specify a feature branch explicitly"
      usage >&2
      exit 1
    fi
  else
    FEATURE="${args[0]}"
    MAIN="${args[1]}"
  fi
}

validate_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "not inside a git repository"
    exit 1
  fi
}

validate_branches() {
  if [[ "$FEATURE" == "$MAIN" ]]; then
    error "feature branch and main branch must be different (both are '${FEATURE}')"
    exit 1
  fi

  if ! branch_exists_locally "$FEATURE" && ! branch_exists_on_remote "$FEATURE"; then
    error "feature branch '${FEATURE}' does not exist locally or on ${REMOTE}"
    exit 1
  fi
}

stash_if_dirty() {
  if is_worktree_dirty; then
    log "Stashing uncommitted changes..."
    git stash push -u -m "sync-pr-auto-stash-$(date +%s)"
    STASHED=true
  fi
}

fetch_main() {
  log "Fetching ${REMOTE}/${MAIN}..."
  git fetch --show-forced-updates "$REMOTE" "$MAIN"
}

verify_main_on_remote() {
  if ! git rev-parse --verify --quiet "${REMOTE}/${MAIN}"; then
    error "${REMOTE}/${MAIN} does not exist after fetch"
    exit 1
  fi
}

checkout_feature_if_needed() {
  if [[ "$FEATURE" == "$ORIGINAL_BRANCH" ]]; then
    return 0
  fi
  log "Checking out ${FEATURE}..."
  git checkout "$FEATURE"
}

rebase_onto_main() {
  log "Rebasing ${FEATURE} onto ${REMOTE}/${MAIN}..."
  if ! git rebase "${REMOTE}/${MAIN}"; then
    REBASE_CONFLICT=true
    exit 1
  fi
}

pop_stash() {
  if [[ "$STASHED" == true ]]; then
    log "Restoring stashed changes..."
    git stash pop
  fi
}

push_feature() {
  [[ "$PUSH" == true ]] || return 0

  if ! branch_exists_on_remote "$FEATURE"; then
    error "cannot push: '${FEATURE}' does not exist on ${REMOTE}"
    exit 1
  fi

  log "Fetching ${REMOTE}/${FEATURE} for push lease..."
  git fetch "$REMOTE" "$FEATURE"

  log "Force pushing ${FEATURE} to ${REMOTE} with lease..."
  git push --force-with-lease "$REMOTE" "$FEATURE"
}

main() {
  trap on_exit EXIT

  parse_args "$@"
  validate_repo

  ORIGINAL_BRANCH="$(git branch --show-current)"

  validate_branches
  stash_if_dirty
  fetch_main
  verify_main_on_remote
  checkout_feature_if_needed
  rebase_onto_main

  SUCCEEDED=true
  trap - EXIT

  push_feature
  pop_stash

  if [[ "$PUSH" == true ]]; then
    log "Successfully rebased and pushed ${FEATURE} onto ${REMOTE}/${MAIN}."
  else
    log "Successfully rebased ${FEATURE} onto ${REMOTE}/${MAIN}."
  fi
}

main "$@"
