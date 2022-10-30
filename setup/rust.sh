#!/bin/sh

# Install Rust
curl https://sh.rustup.rs -sSf | sh -s -- -y

# Lua formatter
cargo install stylua