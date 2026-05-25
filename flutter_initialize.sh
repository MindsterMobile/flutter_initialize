#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# DEBUG MODE
# ------------------------------------------------------------------------------
DEBUG=0
[[ "$DEBUG" == "1" ]] && set -x

trap 'echo -e "\n❌ ERROR at line $LINENO → $BASH_COMMAND\n"' ERR

# ------------------------------------------------------------------------------
# COLORS
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log() { echo -e "${CYAN}👉 $*${RESET}"; }
ok()  { echo -e "${GREEN}✅ $*${RESET}"; }
warn(){ echo -e "${YELLOW}⚠️  $*${RESET}"; }
err() { echo -e "${RED}❌ $*${RESET}"; }

# ------------------------------------------------------------------------------
# INPUT (safe for curl)
# ------------------------------------------------------------------------------
read_input() {
  local prompt="$1"
  local val=""
  while true; do
    read -rp "$prompt" val < /dev/tty || true
    [[ -n "$val" ]] && break
  done
  echo "$val"
}

# ------------------------------------------------------------------------------
# VALIDATION
# ------------------------------------------------------------------------------
validate_ssh_repo() {
  local url="$1"

  if [[ ! "$url" =~ ^git@github.com: ]]; then
    err "Must use SSH format → git@github.com:user/repo.git"
    return 1
  fi

  if ! git ls-remote "$url" &>/dev/null; then
    err "Cannot access repo → $url"
    err "Check: SSH key / repo exists / permissions"
    return 1
  fi
}

validate_project_name() {
  [[ "$1" =~ ^[a-z][a-z0-9_]*$ ]] || return 1
}

check_ssh_auth() {
  log "Checking SSH connection to GitHub..."
  if ! ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    warn "SSH not fully verified. Make sure your key is added to GitHub."
  else
    ok "SSH connection OK"
  fi
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {

  clear
  echo -e "${BOLD}🚀 Flutter Project Initializer (SSH Mode)${RESET}"
  printf '=%.0s' {1..50}; echo ""

  # ------------------------------------------------------------------------------
  # INPUT
  # ------------------------------------------------------------------------------
  BASE_REPO=$(read_input "📦 Base Template Repo (SSH): ")
  PROJECT_NAME=$(read_input "📦 Project Name (snake_case): ")
  APP_NAME=$(read_input "📱 App Name: ")
  BUNDLE_ID=$(read_input "🆔 Bundle ID: ")
  TARGET_REPO=$(read_input "🔗 Target Repo (SSH): ")
  FVM_VERSION=$(read_input "🧩 Flutter Version: ")

  # ------------------------------------------------------------------------------
  # VALIDATION
  # ------------------------------------------------------------------------------
  log "Validating inputs..."

  validate_project_name "$PROJECT_NAME" || {
    err "Invalid project name (use snake_case)"
    exit 1
  }

  check_ssh_auth

  validate_ssh_repo "$BASE_REPO" || exit 1

  # Target repo might be empty → don't hard fail
  if ! git ls-remote "$TARGET_REPO" &>/dev/null; then
    warn "Target repo might be empty or not created yet"
  fi

  ok "Inputs validated"

  # ------------------------------------------------------------------------------
  # CONFIRM
  # ------------------------------------------------------------------------------
  echo ""
  echo -e "${YELLOW}CONFIRM${RESET}"
  printf '%.0s─' {1..40}; echo ""
  echo "Base Repo   : $BASE_REPO"
  echo "Project     : $PROJECT_NAME"
  echo "Target Repo : $TARGET_REPO"
  printf '%.0s─' {1..40}; echo ""

  confirm=$(read_input "Continue? (y/n): ")
  [[ "$confirm" != "y" ]] && exit 0

  # ------------------------------------------------------------------------------
  # WORK DIR
  # ------------------------------------------------------------------------------
  WORK_DIR="$(pwd)/temp_${PROJECT_NAME}"
  rm -rf "$WORK_DIR"

  # ------------------------------------------------------------------------------
  # STEP 1: CLONE BASE
  # ------------------------------------------------------------------------------
  log "Cloning base project..."
  git clone --depth=1 "$BASE_REPO" "$WORK_DIR" || {
    err "Clone failed"
    exit 1
  }
  ok "Cloned successfully"

  cd "$WORK_DIR"

  # ------------------------------------------------------------------------------
  # STEP 2: RESET GIT
  # ------------------------------------------------------------------------------
  log "Resetting git history..."
  rm -rf .git

  # ------------------------------------------------------------------------------
  # STEP 3: UPDATE PROJECT
  # ------------------------------------------------------------------------------
  log "Updating project..."

  if [[ -f pubspec.yaml ]]; then
    if sed --version &>/dev/null 2>&1; then
      sed -i "s/^name:.*/name: ${PROJECT_NAME}/" pubspec.yaml
    else
      sed -i '' "s/^name:.*/name: ${PROJECT_NAME}/" pubspec.yaml
    fi
    ok "Updated pubspec"
  else
    warn "pubspec.yaml not found"
  fi

  # ------------------------------------------------------------------------------
  # STEP 4: FVM SETUP
  # ------------------------------------------------------------------------------
  log "Setting Flutter version..."

  if command -v fvm &>/dev/null; then
    fvm install "$FVM_VERSION" || warn "FVM install failed"
    fvm use "$FVM_VERSION" --force || warn "FVM use failed"
    ok "FVM configured"
  else
    warn "FVM not installed → skipping"
  fi

  # ------------------------------------------------------------------------------
  # STEP 5: PUSH
  # ------------------------------------------------------------------------------
  log "Pushing to target repo..."

  git init
  git add .
  git commit -m "Initial commit ($PROJECT_NAME)"
  git branch -M main
  git remote add origin "$TARGET_REPO"

  git push -u origin main || {
    err "Push failed → check SSH access & repo exists"
    exit 1
  }

  ok "🎉 Project pushed successfully!"

  echo ""
  echo "Clone your project:"
  echo "git clone $TARGET_REPO"
}

main