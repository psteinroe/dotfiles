{ stdenvNoCC, fetchurl, lib }:

let
  version = "0.17.1";

  sources = {
    "aarch64-darwin" = {
      url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-darwin-arm64";
      sha256 = "320e7a5ceef68ad1f98db7fc44aa5901a0650de6d6651af7850570b70a4367fd";
    };
    "x86_64-darwin" = {
      url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-darwin-x64";
      sha256 = "5f34c97f5f3e26dc42ba65e8ab630e06eff2cc06f35738b24759a77cf818d28d";
    };
    "aarch64-linux" = {
      url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-linux-arm64";
      sha256 = "db23ed99b00138947464d0a7a3e0018299f2d8f5198ac32dd039c2650d00f1fa";
    };
    "x86_64-linux" = {
      url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-linux-x64";
      sha256 = "518a0898c632bbd069a2c930ad72cf66242cb1edda1e0e408a6b361246ece7da";
    };
  };

  src = fetchurl (sources.${stdenvNoCC.hostPlatform.system}
    or (throw "plannotator: unsupported system ${stdenvNoCC.hostPlatform.system}"));
in
stdenvNoCC.mkDerivation {
  pname = "plannotator";
  inherit version src;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/plannotator"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Plan annotation hook for AI coding agents";
    homepage = "https://plannotator.ai";
    license = licenses.mit;
    platforms = builtins.attrNames sources;
    mainProgram = "plannotator";
  };
}
