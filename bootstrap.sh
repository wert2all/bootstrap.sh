#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration ---
DEFAULT_SSH_KEY_NAME="wert2all_ssh_key"
ANSIBLE_REPO_URL="git@github.com:wert2all/projects-ansible-config.git"
DOTFILES_REPO_URL="git@github.com:wert2all/dot-files.git"

WORK_DIR="$HOME/work"
INFRA_PARENT="$WORK_DIR/infra"

# --- Colors and Styles ---
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# --- Helper Functions ---
info() { echo -e "${BLUE}${BOLD}󰋼 INFO:${RESET} $1"; }
success() { echo -e "${GREEN}${BOLD}✔ SUCCESS:${RESET} $1"; }
error() { echo -e "${RED}${BOLD}✘ ERROR:${RESET} $1"; }
header() { echo -e "\n${CYAN}${BOLD}=== $1 ===${RESET}\n"; }

cleanup() {
    if [ -n "${BW_SESSION:-}" ]; then
        info "Locking Bitwarden vault..."
        bw lock >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

install_dependencies() {
    local distro="unknown"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="$ID"
    elif [ -f /etc/arch-release ]; then
        distro="arch"
    fi

    info "Detected distribution: ${BOLD}$distro${RESET}"

    case "$distro" in
    "arch")
        sudo pacman -Syu --noconfirm jq pnpm git ansible
        ;;
    "ubuntu" | "debian" | "pop" | "linuxmint")
        sudo apt update && sudo apt install -y jq pnpm git ansible
        ;;
    "opensuse-tumbleweed" | "opensuse-leap" | "opensuse")
        sudo zypper install -y jq pnpm git ansible
        ;;
    "fedora")
        sudo dnf install -y jq pnpm git ansible
        ;;
    *)
        error "Unsupported distro ($distro). Install dependencies manually."
        exit 1
        ;;
    esac
}

setup_bitwarden_cli() {
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"

    if ! command -v bw &>/dev/null; then
        info "Installing Bitwarden CLI..."
        pnpm add -g @bitwarden/cli
    fi
}

fetch_ssh_keys() {
    local key_name=$1
    mkdir -p ~/.ssh && chmod 700 ~/.ssh

    # Check if logged in
    local bw_status=$(bw status)
    if [[ $(echo "$bw_status" | jq -r '.status') == "unauthenticated" ]]; then
        bw login
    fi

    # Unlock and set session
    if [ -z "${BW_SESSION:-}" ]; then
        info "Unlocking vault..."
        BW_SESSION=$(bw unlock --raw)
        export BW_SESSION
    fi

    info "Fetching keys for: ${BOLD}$key_name${RESET}..."
    local item_json=$(bw get item "$key_name" --session "$BW_SESSION")

    echo "$item_json" | jq -r '.sshKey.publicKey' >~/.ssh/id_rsa.pub
    echo "$item_json" | jq -r '.sshKey.privateKey' >~/.ssh/id_rsa

    chmod 600 ~/.ssh/id_rsa
    chmod 644 ~/.ssh/id_rsa.pub

    # Restart agent and add key
    info "Refreshing ssh-agent..."
    eval "$(ssh-agent -s)" >/dev/null
    ssh-add ~/.ssh/id_rsa
}

clone_or_update() {
    local repo_url=$1
    local dest_parent=$2
    local repo_name=$(basename "$repo_url" .git)
    local full_path="$dest_parent/$repo_name"

    mkdir -p "$dest_parent"

    if [ -d "$full_path" ]; then
        info "Repository ${BOLD}$repo_name${RESET} already exists. ${YELLOW}Skipping pull as requested.${RESET}"
    else
        info "Cloning ${BOLD}$repo_name${RESET} into $dest_parent..."
        (cd "$dest_parent" && git clone "$repo_url")
        success "Repository $repo_name cloned successfully."
    fi
}

# --- Main Script ---
clear
echo -e "${YELLOW}${BOLD}  ⚡ LINUX BOOTSTRAPPER ⚡  ${RESET}"

header "Step 1: System Dependencies"
install_dependencies

header "Step 2: Bitwarden Integration"
setup_bitwarden_cli
echo -n "   Enter SSH key name in Bitwarden [Default: $DEFAULT_SSH_KEY_NAME]: "
read -r INPUT_KEY_NAME
TARGET_KEY_NAME=${INPUT_KEY_NAME:-$DEFAULT_SSH_KEY_NAME}

header "Step 3: Secret Retrieval"
fetch_ssh_keys "$TARGET_KEY_NAME"

header "Step 4: Repository Setup"
info "Scanning GitHub SSH fingerprint..."
ssh-keygen -R github.com 2>/dev/null || true
ssh-keyscan -H github.com >>~/.ssh/known_hosts 2>/dev/null

clone_or_update "$ANSIBLE_REPO_URL" "$INFRA_PARENT"
clone_or_update "$DOTFILES_REPO_URL" "$WORK_DIR"

echo -e "\n${GREEN}${BOLD}✨ ALL DONE! Your environment is ready. ✨${RESET}\n"
info "Infrastructure: ${BOLD}$INFRA_PARENT/$(basename "$ANSIBLE_REPO_URL" .git)${RESET}"
info "Dotfiles:       ${BOLD}$WORK_DIR/$(basename "$DOTFILES_REPO_URL" .git)${RESET}"
