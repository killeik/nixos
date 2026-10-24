{ buildGoModule, fetchFromGitHub }:

buildGoModule {
  pname = "mqtt2prometheus";
  version = "unstable-2026-02-16";
  src = fetchFromGitHub {
    owner = "hikhvar";
    repo = "mqtt2prometheus";
    rev = "c324374c71ae1102c450d310e8efbbe8db9cbcb5";
    hash = "sha256-HJnE2eKa2SXGa99YuzUxi2PONyA2kIuHpbzOoHzGRDg=";
  };
  vendorHash = "sha256-ceQ3M9C/Bk+3WzKfk6t/OBNLV/4YbBvtb4vNIVW2Y/0=";
  subPackages = [ "cmd" ];
  env.CGO_ENABLED = 0;
  ldflags = [
    "-s"
    "-w"
  ];
  postInstall = ''
    mv $out/bin/cmd $out/bin/mqtt2prometheus
  '';
}
