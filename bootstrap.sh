#!/bin/bash

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

# Function to detect distro and install packages
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
        info "Installing dependencies via pacman..."
        sudo pacman -Syu --noconfirm jq pnpm git ansible
        ;;
    "ubuntu" | "debian" | "pop" | "linuxmint")
        info "Installing dependencies via apt..."
        sudo apt update && sudo apt install -y jq pnpm git ansible
        ;;
    "opensuse-tumbleweed" | "opensuse-leap" | "opensuse")
        info "Installing dependencies via zypper..."
        sudo zypper install -y jq pnpm git ansible
        ;;
    "fedora")
        info "Installing dependencies via dnf..."
        sudo dnf install -y jq pnpm git ansible
        ;;
    *)
        error "Unsupported distro ($distro). Please install jq, pnpm, git, and ansible manually."
        exit 1
        ;;
    esac
}

# Function to setup pnpm paths and install Bitwarden CLI
setup_bitwarden_cli() {
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"

    if ! command -v bw &>/dev/null; then
        info "Bitwarden CLI not found. Installing via pnpm..."
        pnpm add -g @bitwarden/cli
        success "Bitwarden CLI installed."
    else
        info "Bitwarden CLI is already installed."
    fi
}

# Function to fetch SSH keys from Bitwarden
fetch_ssh_keys() {
    local key_name=$1

    mkdir -p ~/.ssh && chmod 700 ~/.ssh

    # Check if we need to unlock/login
    if [ -z "$BW_SESSION" ]; then
        info "Authentication needed for Bitwarden."
        if ! bw status | jq -e '.status == "authenticated"' >/dev/null; then
            bw login
        fi
        export BW_SESSION=$(bw unlock --raw)
    fi

    info "Fetching keys for: ${BOLD}$key_name${RESET}..."
    local item_json=$(bw get item "$key_name" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$item_json" ]; then
        error "Could not find item '$key_name' in your vault."
        exit 1
    fi

    echo "$item_json" | jq -r '.sshKey.publicKey' >~/.ssh/id_rsa.pub
    echo "$item_json" | jq -r '.sshKey.privateKey' >~/.ssh/id_rsa

    if [ ! -s ~/.ssh/id_rsa ]; then
        error "Private key field is empty in Bitwarden!"
        exit 1
    fi

    chmod 600 ~/.ssh/id_rsa
    chmod 644 ~/.ssh/id_rsa.pub
    success "SSH keys configured in ~/.ssh/"
}

# Function to clone or update a repository
clone_or_update() {
    local repo_url=$1
    local dest_parent=$2

    # Extract repo name from URL
    local repo_name=$(basename "$repo_url" .git)
    local full_path="$dest_parent/$repo_name"

    # Ensure parent directory exists
    mkdir -p "$dest_parent"

    if [ -d "$full_path/.git" ]; then
        info "Repository ${BOLD}$repo_name${RESET} already exists. Pulling updates..."
        (cd "$full_path" && git pull)
    elif [ -d "$full_path" ]; then
        error "Directory $full_path exists but is not a git repository. Skipping."
    else
        info "Cloning ${BOLD}$repo_name${RESET} into $dest_parent..."
        if (cd "$dest_parent" && git clone "$repo_url"); then
            success "Repository $repo_name cloned successfully."
        else
            error "Failed to clone $repo_url."
            return 1
        fi
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
install_dependencies
success "System tools ready."

# 2. Bitwarden CLI Setup
header "🔐 Step 2: Bitwarden Integration"
setup_bitwarden_cli

echo -e "${YELLOW}${BOLD}󱊄 ACTION REQUIRED:${RESET}"
echo -n "   Enter SSH key name in Bitwarden [Default: $DEFAULT_SSH_KEY_NAME]: "
read -r INPUT_KEY_NAME
TARGET_KEY_NAME=${INPUT_KEY_NAME:-$DEFAULT_SSH_KEY_NAME}

# 3. SSH Key Retrieval
header "🔑 Step 3: Secret Retrieval"
fetch_ssh_keys "$TARGET_KEY_NAME"

# 4. Repository Setup
header "📁 Step 4: Repository Setup"
info "Scanning GitHub SSH fingerprint..."
ssh-keyscan -H github.com >>~/.ssh/known_hosts 2>/dev/null

# Clone Ansible repo into work/infra
clone_or_update "$ANSIBLE_REPO_URL" "$INFRA_PARENT"

# Clone dot-files repo into work/
clone_or_update "$DOTFILES_REPO_URL" "$WORK_DIR"

echo -e "\n${GREEN}${BOLD}✨ ALL DONE! Your environment is ready. ✨${RESET}\n"
info "Infrastructure: ${BOLD}$INFRA_PARENT/$(basename "$ANSIBLE_REPO_URL" .git)${RESET}"
info "Dotfiles:       ${BOLD}$WORK_DIR/$(basename "$DOTFILES_REPO_URL" .git)${RESET}"
