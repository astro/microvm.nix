# TODO: upstream to nixpkgs once it no longer requires rust nightly
{ lib, fetchFromGitHub, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "alioth";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "google";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-brlbLjlpOYz+Qzn2IG9y6ty+yF6MohG5IhI+BHu6LuA=";
  };

  patches = [
    ./alioth-blk-ro.patch
  ];

  cargoHash = "sha256-jRyRy1aKLk92bUvw4Q4lE8q7bnTDgJ7pWCMIW4nBo1A=";
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
