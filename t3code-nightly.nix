{ stdenv, fetchurl, autoPatchelfHook, patchelf, makeWrapper, lib, git, gh }:

let
  # patchelf 0.19.2 creates overlapping LOAD segments in this Node SEA executable.
  compatiblePatchelf = patchelf.overrideAttrs {
    version = "0.15.2";
    src = fetchurl {
      url = "https://github.com/NixOS/patchelf/releases/download/0.15.2/patchelf-0.15.2.tar.bz2";
      hash = "sha256-F3RfVkFZyOIo/EEtplogSLhGxLa0Igt3y/IkFuAvLXw=";
    };
  };
in
stdenv.mkDerivation rec {
  pname = "t3code-nightly";
  version = "0.1.1-nightly.20261020.3411";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/t3-${version}-linux-x64.tar.gz";
    hash = "sha256-J8TCjci4aHpBeU2mOOTf4CuW5a7faN+oSTmm4lDedZI=";
  };

  nativeBuildInputs = [ compatiblePatchelf autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontBuild = true;
  # Keep the embedded Node SEA application payload intact.
  dontStrip = true;

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/t3 --version
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/t3 $out/bin
    cp -r . $out/libexec/t3/
    makeWrapper $out/libexec/t3/t3 $out/bin/t3 \
      --prefix PATH : ${lib.makeBinPath [ git gh ]} \
      --set-default T3CODE_RESOURCE_MONITOR_PATH $out/libexec/t3/resource-monitor/linux-x64/t3-resource-monitor
    runHook postInstall
  '';

  meta.platforms = [ "x86_64-linux" ];
}
