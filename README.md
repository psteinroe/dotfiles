# Dotfiles

![Maintenance](https://img.shields.io/maintenance/yes/2022.svg)

These are my Dotfiles, a collection of [Neovim](https://neovim.io/), [tmux](https://tmux.github.io/), [zsh](http://zsh.sourceforge.net/), and other tools.

## Initial Setup and Installation

```sh
git clone git@github.com:psteinroe/dotfiles.git ~/.dotfiles
cd ~/.dotfiles/
./install
```

Dotbot will create symlinks from all necessary files in the folder.

## Setting Up a New Computer

```shell
# Install all available updates
sudo softwareupdate -i -a

# Install Homebrew
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Load Homebrew
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# Install GitHub ClI
brew install gh

# Login with SSH
gh auth login

# Clone this repository
git clone git@github.com:psteinroe/dotfiles.git ~/.dotfiles
cd ~/.dotfiles/

# Install
./install

# Setup
./setup/init.sh
```

## Syncing Homebrew

Install from Brewfile: `brew bundle`

Cleanup: `brew bundle --force cleanup`

## Acknowledgements

- https://github.com/kogakure/dotfiles
- https://github.com/NvChad/NvChad
