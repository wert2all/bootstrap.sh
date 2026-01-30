#!/bin/bash

# --- Configuration ---
DEFAULT_SSH_KEY_NAME="wert2all_ssh_key"
ANSIBLE_REPO_URL="git@github.com:wert2all/projects-ansible-config.git"
WORK_DIR="$HOME/work"
INFRA_DIR="$WORK_DIR/infra"

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

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# Function to clone or update a repository
clone_or_update() {
    local repo_url=$1
    local target_dir=$2

    info "Processing repository into: ${BOLD}$target_dir${RESET}"

    # 1. If it's already a git repo, just pull
    if [ -d "$target_dir/.git" ]; then
        info "Repository already exists. Pulling updates..."
        (cd "$target_dir" && git pull)

    # 2. If directory doesn't exist OR it exists but is empty, we can clone
    elif [ ! -d "$target_dir" ] || [ -z "$(ls -A "$target_dir")" ]; then
        info "Cloning into $target_dir..."
        if git clone "$repo_url" "$target_dir"; then
            success "Cloned successfully."
        else
            error "Failed to clone $repo_url."
            return 1
        fi

    # 3. If directory exists and has files (but no .git), we don't want to break anything
    else
        error "Directory $target_dir is not empty and not a git repo. Manual intervention required."
        return 1
    fi
}

# --- Main Script ---
clear
echo -e "${YELLOW}${BOLD}"
echo "  ⚡ LINUX BOOTSTRAPPER ⚡  "
echo "---------------------------"
echo -e "${RESET}"

# 1. System Dependencies
header "📦 Step 1: System Dependencies"
distro=$(detect_distro)
info "Detected distribution: ${BOLD}$distro${RESET}"

case "$distro" in
"arch")
    info "Installing dependencies via pacman..."
    sudo pacman -Syu --noconfirm jq pnpm git ansible
    ;;
"ubuntu" | "debian" | "pop" | "linuxmint")
    info "Installing dependencies via apt..."
    sudo apt update && sudo apt install -y jq pnpm git ansible
    ;;
*)
    error "Unsupported distro. Please install jq, pnpm, git, and ansible manually."
    exit 1
    ;;
esac
success "System tools ready."

# 2. Bitwarden CLI Setup
header "🔐 Step 2: Bitwarden Integration"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"

if ! command -v bw &>/dev/null; then
    info "Installing Bitwarden CLI via pnpm..."
    pnpm add -g @bitwarden/cli
fi

echo -e "${YELLOW}${BOLD}󱊄 ACTION REQUIRED:${RESET}"
echo -n "   Enter SSH key name in Bitwarden [Default: $DEFAULT_SSH_KEY_NAME]: "
read -r INPUT_KEY_NAME
SSH_KEY_NAME=${INPUT_KEY_NAME:-$DEFAULT_SSH_KEY_NAME}

if [ -z "$BW_SESSION" ]; then
    info "Authentication needed for Bitwarden."
    bw login
    export BW_SESSION=$(bw unlock --raw)
fi

# 3. SSH Key Retrieval
header "🔑 Step 3: Secret Retrieval"
mkdir -p ~/.ssh && chmod 700 ~/.ssh

info "Fetching keys for: ${BOLD}$SSH_KEY_NAME${RESET}..."
ITEM_JSON=$(bw get item "$SSH_KEY_NAME" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ITEM_JSON" ]; then
    error "Could not find item '$SSH_KEY_NAME' in your vault."
    exit 1
fi

echo "$ITEM_JSON" | jq -r '.sshKey.publicKey' >~/.ssh/id_rsa.pub
echo "$ITEM_JSON" | jq -r '.sshKey.privateKey' >~/.ssh/id_rsa

if [ ! -s ~/.ssh/id_rsa ]; then
    error "Private key field is empty!"
    exit 1
fi

chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
success "SSH keys configured."

# 4. Repository Setup
header "📁 Step 4: Repository Setup"
info "Scanning GitHub SSH fingerprint..."
ssh-keyscan -H github.com >>~/.ssh/known_hosts 2>/dev/null

# Create work directory (base only)
mkdir -p "$WORK_DIR"

# Execute clone/update
clone_or_update "$ANSIBLE_REPO_URL" "$INFRA_DIR"

echo -e "\n${GREEN}${BOLD}✨ ALL DONE! Your environment is ready. ✨${RESET}\n"
