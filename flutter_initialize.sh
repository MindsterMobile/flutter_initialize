#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# DEBUG MODE (0 = off, 1 = on)
# ------------------------------------------------------------------------------
DEBUG=0
[[ "$DEBUG" == "1" ]] && set -x

# ------------------------------------------------------------------------------
# ERROR HANDLER
# ------------------------------------------------------------------------------
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
# SAFE INPUT (fixes infinite loop + curl issue)
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
validate_repo() {
  local url="$1"
  if ! git ls-remote "$url" &>/dev/null; then
    err "Cannot access repo → $url"
    err "Check: exists / public / correct URL / permissions"
    return 1
  fi
}

validate_project_name() {
  [[ "$1" =~ ^[a-z][a-z0-9_]*$ ]] || return 1
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {

  clear
  echo -e "${BOLD}🚀 Flutter Project Initializer${RESET}"
  printf '=%.0s' {1..50}; echo ""

  # ------------------------------------------------------------------------------
  # INPUT
  # ------------------------------------------------------------------------------
  BASE_REPO=$(read_input "📦 Base Template Repo URL: ")
  PROJECT_NAME=$(read_input "📦 Project Name (snake_case): ")
  APP_NAME=$(read_input "📱 App Name: ")
  BUNDLE_ID=$(read_input "🆔 Bundle ID (com.company.app): ")
  TARGET_REPO=$(read_input "🔗 Target Repo URL: ")
  FVM_VERSION=$(read_input "🧩 Flutter Version: ")

  # ------------------------------------------------------------------------------
  # VALIDATION
  # ------------------------------------------------------------------------------
  log "Validating inputs..."

  validate_project_name "$PROJECT_NAME" || {
    err "Invalid project name"
    exit 1
  }

  validate_repo "$BASE_REPO" || exit 1
  validate_repo "$TARGET_REPO" || {
    warn "Target repo might be empty or not created yet"
  }

  ok "Inputs validated"

  # ------------------------------------------------------------------------------
  # SUMMARY
  # ------------------------------------------------------------------------------
  echo ""
  echo -e "${YELLOW}CONFIRMATION${RESET}"
  printf '%.0s─' {1..40}; echo ""
  echo "Base Repo   : $BASE_REPO"
  echo "Project     : $PROJECT_NAME"
  echo "App Name    : $APP_NAME"
  echo "Bundle ID   : $BUNDLE_ID"
  echo "Target Repo : $TARGET_REPO"
  echo "Flutter     : $FVM_VERSION"
  printf '%.0s─' {1..40}; echo ""

  confirm=$(read_input "Continue? (y/n): ")
  [[ "$confirm" != "y" ]] && exit 0

  # ------------------------------------------------------------------------------
  # WORK DIR
  # ------------------------------------------------------------------------------
  WORK_DIR="$(pwd)/temp_${PROJECT_NAME}"
  rm -rf "$WORK_DIR"

  # ------------------------------------------------------------------------------
  # STEP 1: CLONE BASE TEMPLATE
  # ------------------------------------------------------------------------------
  log "Cloning base project..."
  git clone --depth=1 "$BASE_REPO" "$WORK_DIR" || {
    err "Failed to clone base repo"
    exit 1
  }
  ok "Base project cloned"

  cd "$WORK_DIR"

  # ------------------------------------------------------------------------------
  # STEP 2: REMOVE OLD GIT
  # ------------------------------------------------------------------------------
  log "Cleaning git history..."
  rm -rf .git

  # ------------------------------------------------------------------------------
  # STEP 3: RENAME PROJECT
  # ------------------------------------------------------------------------------
  log "Updating project configuration..."

  if [[ -f pubspec.yaml ]]; then
    if sed --version &>/dev/null 2>&1; then
      sed -i "s/^name:.*/name: ${PROJECT_NAME}/" pubspec.yaml
    else
      sed -i '' "s/^name:.*/name: ${PROJECT_NAME}/" pubspec.yaml
    fi
    ok "pubspec updated"
  else
    warn "pubspec.yaml not found"
  fi

  # ------------------------------------------------------------------------------
  # STEP 4: FVM SETUP (OPTIONAL SAFE)
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
  # STEP 5: PUSH TO TARGET REPO
  # ------------------------------------------------------------------------------
  log "Pushing to target repo..."

  git init
  git add .
  git commit -m "Initial commit ($PROJECT_NAME)"
  git branch -M main
  git remote add origin "$TARGET_REPO"

  git push -u origin main || {
    err "Push failed → check repo exists & permissions"
    exit 1
  }

  ok "Project pushed successfully 🎉"

  # ------------------------------------------------------------------------------
  # DONE
  # ------------------------------------------------------------------------------
  echo ""
  echo -e "${GREEN}🚀 DONE!${RESET}"
  echo ""
  echo "Clone your project:"
  echo "git clone $TARGET_REPO"
  echo ""
}

main