{ self, nixpkgs, system }:

let
  pkgs = nixpkgs.legacyPackages.${system};

  kernelWithConfig = configfile: (pkgs.linuxPackages_custom {
    inherit (pkgs.linuxPackages_latest.kernel) version src;
    inherit configfile;
  }).kernel;

in rec {
  virtioKernel = kernelWithConfig ./kernel.config;

  cloudHypervisorKernel =
    let
      arch = builtins.head (builtins.split "-" system);
      config = pkgs.stdenv.mkDerivation {
        name = "cloud-hypervisor-kernel.config";
        src = pkgs.cloud-hypervisor.src;
        phases = [ "unpackPhase" "installPhase" ];
        installPhase = ''
          cp resources/linux-config-${arch} $out
        '';
      };
    in
      kernelWithConfig config;
}
