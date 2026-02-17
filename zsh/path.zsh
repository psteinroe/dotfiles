path=(
  $HOME/Developer/dotfiles/bin
  $HOME/.local/bin
  /run/current-system/sw/bin          # nix-darwin packages
  /etc/profiles/per-user/$USER/bin    # home-manager packages
  $HOME/.nix-profile/bin              # nix profile fallback
  $HOME/.cargo/bin                    # Rust
  $HOME/go/bin                        # Go
  $HOME/Library/pnpm                  # PNPM
  $HOME/Developer/postgres-language-server.git/main/target/debug  # PGLS debug
  /opt/homebrew/opt/libpq/bin         # PostgreSQL tools
  /usr/local/sbin
  $path
)
