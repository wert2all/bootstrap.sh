#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration ---
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

authorize_bitwarden() {
    # Check if logged in
    bw_status=$(bw status | jq -r '.status')
    if [ "$bw_status" == "unauthenticated" ]; then
        info "Logging into Bitwarden..."
        export BW_SESSION=$(bw login --raw)
    else
        export BW_SESSION=$(bw unlock --raw)
    fi

    if [ -z "${BW_SESSION:-}" ]; then
        error "Failed to obtain Bitwarden session. Please check your credentials."
        exit 1
    fi

}

clone_or_update() {
    local repo_url=$1
    local dest_parent=$2

    local repo_name
    repo_name=$(echo "$repo_url" | sed 's#.*/##; s#\.git$##')

    local full_path="$dest_parent/$repo_name"

    mkdir -p "$dest_parent"

    if [ -d "$full_path/.git" ]; then
        info "Repository ${BOLD}$repo_name${RESET} already exists. Skipping."
    else
        info "Cloning ${BOLD}$repo_name${RESET} into $dest_parent..."
        git clone "$repo_url" "$full_path"
        success "Repository $repo_name cloned successfully."
    fi
}

expose_all_ssh_keys_from_bitwarden() {
    bw list items --session "$BW_SESSION" | jq -c '[.[] | select(.sshKey != null)]'
}

expose_key_from_bitwarden() {
    local bitwarden_item=$1
    local dest_parent=$2
    local key_name=$3

    echo -n "   Enter SSH key name in Bitwarden: "
    read -r bitwarden_item

    mkdir -p "$dest_parent" && chmod 700 "$dest_parent"

    info "Fetching keys for: ${BOLD}$bitwarden_item${RESET}..."
    local matched_item
    matched_item=$(echo "$filtered_items_json" | jq -e -c ".[] | select(.name == \"$bitwarden_item\")" 2>/dev/null || true)

    if [ -z "$matched_item" ]; then
        error "Item '$bitwarden_item' not found in the filtered SSH list."
        exit 1
    fi

    echo "$matched_item" | jq -r '.sshKey.publicKey' >"$dest_parent"/"$key_name".pub
    echo "$matched_item" | jq -r '.sshKey.privateKey' >"$dest_parent"/"$key_name"

    chmod 600 "$dest_parent"/"$key_name"
    chmod 644 "$dest_parent"/"$key_name".pub

    # # Restart agent and add key
    # info "Refreshing ssh-agent..."
    # eval "$(ssh-agent -s)" >/dev/null
    # ssh-add ~/.ssh/id_rsa
}

import_gpg_key() {
    echo -n "   Enter Bitwarden item name for GPG key (stored in Notes): "
    read -r gpg_item_name </dev/tty

    if [ -z "$gpg_item_name" ]; then
        info "Skipping GPG import."
        return
    fi

    info "Fetching GPG key from: ${BOLD}$gpg_item_name${RESET}..."
    local gpg_key_text
    gpg_key_text=$(bw list items --search "$gpg_item_name" --session "$BW_SESSION" | jq -r '.[0].notes')

    if [ "$gpg_key_text" == "null" ] || [ -z "$gpg_key_text" ]; then
        error "No GPG key found in notes of '$gpg_item_name'."
        return 1
    fi

    echo "$gpg_key_text" | gpg --import
    success "GPG key imported."
}

#
# --- Main Script ---
clear
echo -e "${YELLOW}${BOLD}  ⚡ LINUX BOOTSTRAPPER ⚡  ${RESET}"

header "Step 1: System Dependencies"
install_dependencies

header "Step 2: Bitwarden Integration"
setup_bitwarden_cli
authorize_bitwarden

filtered_items_json=$(expose_all_ssh_keys_from_bitwarden)
export filtered_items_json

info "    Select Bitwarden item for user SSH keys:"
expose_key_from_bitwarden "$bitwarden_item" ~/.ssh/ id_rsa
info "    Select Bitwarden item for ansible SSH keys:"
expose_key_from_bitwarden "$bitwarden_item" "$INFRA_PARENT/projects-ansible-config/playbooks/tasks/init/files" ansible

info "Import GPG-key"
import_gpg_key

header "Step 3: Repository Setup"
info "Scanning GitHub SSH fingerprint..."
ssh-keygen -R github.com 2>/dev/null || true
ssh-keyscan -H github.com >>~/.ssh/known_hosts 2>/dev/null

mkdir -p "$WORK_DIR"
mkdir -p "$INFRA_PARENT"

clone_or_update "$ANSIBLE_REPO_URL" "$INFRA_PARENT"
clone_or_update "$DOTFILES_REPO_URL" "$WORK_DIR"

echo -e "\n${GREEN}${BOLD}✨ ALL DONE! Your environment is ready. ✨${RESET}\n"
info "Infrastructure: ${BOLD}$INFRA_PARENT/$(basename "$ANSIBLE_REPO_URL" .git)${RESET}"
info "Dotfiles:       ${BOLD}$WORK_DIR/$(basename "$DOTFILES_REPO_URL" .git)${RESET}"
