#!/bin/sh

# Install Rust
rustup-init --default-toolchain nightly -y

# Lua formatter
cargo install stylua

cargo install cargo-expand

cargo install cargo-insta

rustup component add clippy

# https://github.com/gitext-rs/git-stack
cargo install git-stack git-branch-stash-cli
git stack alias --register
