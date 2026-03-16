#!/usr/bin/env bash
# =============================================================================
# sync-docs.sh
#
# Pulls the latest Convox documentation from the upstream convox/convox repo
# into ./docs/ for local reference. This directory is gitignored since it is
# a copy of upstream content, not original to this project.
#
# The docs are used as context by Claude Code when working on this project.
#
# Usage:
#   ./sync-docs.sh              # Clone/update docs from master branch
#   ./sync-docs.sh <branch>     # Clone/update docs from a specific branch
#   ./sync-docs.sh --clean      # Remove the local docs directory
# =============================================================================

set -euo pipefail

REPO_URL="https://github.com/convox/convox.git"
DOCS_DIR="./docs"
BRANCH="${1:-master}"

info() { echo ">>> $*"; }
err()  { echo "ERROR: $*" >&2; }

if [[ "${1:-}" == "--clean" ]]; then
  info "Removing $DOCS_DIR"
  rm -rf "$DOCS_DIR"
  info "Done."
  exit 0
fi

if ! command -v git &>/dev/null; then
  err "git is required."
  exit 1
fi

if [[ -d "$DOCS_DIR/.git-sparse" ]]; then
  # Update existing checkout
  info "Updating docs from convox/convox ($BRANCH)..."
  cd "$DOCS_DIR"
  git --git-dir=.git-sparse fetch origin "$BRANCH" --depth=1 2>/dev/null
  git --git-dir=.git-sparse checkout FETCH_HEAD -- docs/ 2>/dev/null

  # Flatten: move docs/docs/* to docs/* so the path is ./docs/reference/... not ./docs/docs/reference/...
  if [[ -d "docs" ]]; then
    cp -R docs/* . 2>/dev/null || true
    rm -rf docs
  fi

  cd ..
  info "Docs updated."
else
  # Fresh sparse checkout (only the docs/ directory from the repo)
  info "Pulling docs from convox/convox ($BRANCH)..."
  rm -rf "$DOCS_DIR"
  mkdir -p "$DOCS_DIR"

  # Use a hidden git dir so the docs folder doesn't look like a submodule
  git clone --no-checkout --depth=1 --filter=blob:none --branch="$BRANCH" \
    "$REPO_URL" "$DOCS_DIR/.git-sparse-tmp" 2>/dev/null

  mv "$DOCS_DIR/.git-sparse-tmp/.git" "$DOCS_DIR/.git-sparse"
  rm -rf "$DOCS_DIR/.git-sparse-tmp"

  cd "$DOCS_DIR"
  git --git-dir=.git-sparse config core.sparseCheckout true
  echo "docs/" > .git-sparse/info/sparse-checkout
  git --git-dir=.git-sparse checkout 2>/dev/null

  # Flatten: docs/docs/* -> docs/*
  if [[ -d "docs" ]]; then
    cp -R docs/* . 2>/dev/null || true
    rm -rf docs
  fi

  cd ..
  info "Docs pulled to $DOCS_DIR/"
fi

# Summary
doc_count=$(find "$DOCS_DIR" -name "*.md" | wc -l | tr -d ' ')
info "$doc_count markdown files available in $DOCS_DIR/"
info ""
info "Directory structure:"
find "$DOCS_DIR" -maxdepth 2 -type d | sort | head -30 | sed 's/^/  /'