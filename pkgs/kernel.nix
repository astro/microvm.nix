{ self, nixpkgs, system }:

let
  pkgs = nixpkgs.legacyPackages.${system};
in {
  virtioKernel = (pkgs.linuxPackages_custom {
    inherit (pkgs.linuxPackages.kernel) version src;
    configfile = ./kernel.config;
  }).kernel;
}
