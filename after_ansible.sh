#!/bin/bash

WORK_DIR="$HOME/work"

systemctl enable --user ssh-agent
systemctl start --user ssh-agent

cd $WORK_DIR
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
