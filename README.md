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

The project includes a `setup` folder that has install scripts for everything I need on a new computer. You can run the scripts individually or all at once by running `./setup/init.sh`.

## Syncing Homebrew

Install from Brewfile: `brew bundle`

Cleanup: `brew bundle --force cleanup`

## Acknowledgements

- https://github.com/kogakure/dotfiles
- https://github.com/NvChad/NvChad
