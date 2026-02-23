#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

WORK_DIR="$HOME/work"
PASS_DIR="$HOME/.password-store"
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
  if ! command -v yay &>/dev/null; then
    cd "$WORK_DIR"
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si
  fi

  yay -S --noconfirm \
    zen-browser-bin \
    telegram-desktop-bin \
    discord \
    obsidian \
    google-chrome \
    flatpak

  sudo systemctl enable --now systemd-resolved
  if [ -f /usr/bin/resolvectl ]; then
    echo "resolvconf already installed"
  else
    sudo ln -s /usr/bin/resolvectl /usr/local/bin/resolvconf
  fi

fi

if [[ "$DISTRO" =~ ^(opensuse-tumbleweed|opensuse-leap|opensuse)$ ]]; then
  sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
  sudo zypper addrepo https://dl.google.com/linux/chrome/rpm/stable/x86_64 Google-Chrome
  sudo zypper refresh

  sudo zypper install flatpak google-chrome-stable
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install flathub app.zen_browser.zen md.obsidian.Obsidian io.dbeaver.DBeaverCommunity

  sudo zypper install-new-recommends
fi

flatpak install flathub com.getmailspring.Mailspring

if [ ! -d "$PASS_DIR" ]; then
  pass init "$HOME/.password-store"
  pass git init
  pass git remote add origin git@wert2all.nsupdate.info:wert2all/password-store.git
  pass git fetch --all
  pass git reset --hard origin/main
fi

pnpm install -g opencode-ai @fission-ai/openspec@latest

curl -fsSL https://plannotator.ai/install.sh | bash
