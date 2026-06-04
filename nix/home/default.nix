{
  lib,
  isDarwin ? false,
  isLinux ? false,
  ...
}:

{
  imports = [
    ./common.nix
    ./packages.nix
    ./shell.nix
    ./git.nix
    ./agents.nix
  ]
  ++ lib.optional isDarwin ./darwin.nix
  ++ lib.optional isLinux ./linux.nix;
}
