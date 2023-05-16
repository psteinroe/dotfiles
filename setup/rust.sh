#!/bin/sh

# Install Rust
rustup-init --default-toolchain nightly -y

# Lua formatter
cargo install stylua
