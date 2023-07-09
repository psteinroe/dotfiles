#!/bin/sh

brew bundle --file ~/.dotfiles/Brewfile

# set homebrew bash as default
sudo bash -c 'echo "/opt/homebrew/bin/bash" >> /etc/shells'

chsh -s /opt/homebrew/bin/bash
sudo chsh -s /opt/homebrew/bin/bash
