{ config, lib, pkgs, ... }:

let
  microvm-lib = import ../../lib {
    nixpkgs-lib = lib;
  };

in

{
  imports = [
    ./boot-disk.nix
    ./store-disk.nix
    ./options.nix
    ./asserts.nix
    ./system.nix
    ./mounts.nix
    ./graphics.nix
    ./optimization.nix
  ];

  config = {
    microvm.runner = lib.genAttrs microvm-lib.hypervisors (hypervisor:
      microvm-lib.buildRunner {
        inherit pkgs;
        microvmConfig = config.microvm // {
          inherit (config.networking) hostName;
          inherit hypervisor;
        };
        inherit (config.system.build) toplevel;
      }
    );
  };
}
