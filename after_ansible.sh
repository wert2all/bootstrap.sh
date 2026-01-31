#!/bin/bash

WORK_DIR="$HOME/work"

systemctl enable --user ssh-agent
systemctl start --user ssh-agent

# cd $WORK_DIR
# git clone https://aur.archlinux.org/yay.git
# cd yay
# makepkg -si

yay -S --noconfirm \
  zen-browser-bin

pnpm install -g opencode-ai @fission-ai/openspec@latest

curl -fsSL https://plannotator.ai/install.sh | bash
