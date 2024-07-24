# TODO: upstream to nixpkgs once it no longer requires rust nightly
{ lib, fetchFromGitHub, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "alioth";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "google";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-Dyev6cZSCzia9PN2+QiiqARCt/OT9NcGnrgF7womvUg=";
  };

  cargoHash = "sha256-4oN0v77VQHpyS/fXefYQPuslBAkDuTpjNPE1UiQ/Rz0=";
  separateDebugInfo = true;

  # TODO: Broken
  doCheck = false;

  meta = with lib; {
    homepage = "https://github.com/google/alioth";
    description = "Experimental Type-2 Hypervisor in Rust implemented from scratch";
    license = licenses.asl20;
    mainProgram = "alioth";
    maintainers = with maintainers; [ astro ];
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
