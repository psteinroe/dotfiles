path=(
  $HOME/Developer/dotfiles/bin
  $HOME/.local/bin
  $HOME/.npm-global/bin               # npm global prefix
  /run/current-system/sw/bin          # NixOS/nix-darwin system packages
  /etc/profiles/per-user/$USER/bin    # home-manager packages
  $HOME/.nix-profile/bin              # nix profile fallback
  $HOME/.cargo/bin                    # Rust
  $HOME/go/bin                        # Go
  $path
)

case "$(uname -s)" in
  Darwin)
    path=(
      $HOME/Library/pnpm              # PNPM
      $HOME/Developer/postgres-language-server.git/main/target/debug  # PGLS debug
      /opt/homebrew/opt/libpq/bin     # PostgreSQL tools
      /usr/local/sbin
      $path
    )
    ;;
esac
