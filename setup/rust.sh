#!/bin/sh

# Install Rust
rustup-init --default-toolchain nightly -y

# Lua formatter
cargo install stylua

cargo install cargo-expand

cargo install cargo-insta

rustup component add clippy
