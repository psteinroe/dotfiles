{ stdenvNoCC, fetchurl }:
let
  release = import ./t3code-release.nix;
  platform =
    release.platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "T3 Code is not packaged for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "t3code";
  inherit (release) version;
  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${release.version}/t3-${release.version}-linux-${platform.arch}.tar.gz";
    inherit (platform) hash;
  };
  sourceRoot = "t3-${release.version}-linux-${platform.arch}";
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec/t3code" "$out/bin"
    # Do not patchelf: this would shift the Bun executable's embedded payload.
    cp -a . "$out/libexec/t3code/"
    chmod 0755 "$out/libexec/t3code/t3"
    ln -s "$out/libexec/t3code/t3" "$out/bin/t3"
    runHook postInstall
  '';
}
