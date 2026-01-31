#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

WORK_DIR="$HOME/work"
DISTRO="unknown"

detect_distro() {
  local distro="unknown"
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    distro="$ID"
  elif [ -f /etc/arch-release ]; then
    distro="arch"
  fi
  echo $distro
}

systemctl enable --user ssh-agent
systemctl start --user ssh-agent

DISTRO=$(detect_distro)
if [ "$DISTRO" == "arch" ]; then

  cd $WORK_DIR
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si

  yay -S --noconfirm \
    zen-browser-bin
fi

pnpm install -g opencode-ai @fission-ai/openspec@latest

curl -fsSL https://plannotator.ai/install.sh | bash
