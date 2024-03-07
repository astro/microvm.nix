{ nixbsd }:

{ config, lib, pkgs, ... }:

let
  microvm-lib = import ../../lib {
    nixpkgs-lib = lib;
  };

  regInfo =
    pkgs.closureInfo {
      rootPaths = config.system.build.toplevel;
    };

in

{
  imports = [
    ../microvm/options.nix
    ../microvm/system.nix
  ];

  options = {
    boot.kernelPackages = lib.mkOption {
      type = lib.types.anything;
      default.kernel = config.boot.kernel.package;
    };
    boot.blacklistedKernelModules = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
    };
    boot.initrd.kernelModules = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
    };
    boot.kernelParams = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
    };
    boot.loader.grub.enable = lib.mkEnableOption "GRUB";
    systemd = lib.mkOption {
      type = lib.types.anything;
      default = {};
    };
    microvm.optimize.enable = lib.mkEnableOption "Optimize";
    microvm.storeDisk = lib.mkOption {
      type = lib.types.path;
    };
    virtualisation.efi.firmware = lib.mkOption {
      type = lib.types.any;
      default = null;
    };
  };

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

    # microvm.kernelPath = "${config.boot.kernel.package}/kernel/kernel";
    microvm.kernelPath = config.kernelPath;

    microvm.storeDisk = import (nixbsd + "/lib/make-disk-image.nix") {
      name = "nix-store-image";
      inherit pkgs config lib;
      additionalPaths = [ regInfo ];
      format = "raw";
      onlyNixStore = true;
      label = "nix-store";
      partitionTableType = "none";
      installBootLoader = false;
      touchEFIVars = false;
      diskSize = "auto";
      additionalSpace = "0M";
      copyChannel = false;
      OVMF = {
        firmware = throw "OVMF firmware";
        variables = builtins.toFile "dummy" "";
      };
    } + "/nixos.img";
    virtualisation.efi.firmware = null; #builtins.toFile "dummy" "";

    nixpkgs.config.packageOverride = pkgs: {
      findutils = pkgs.findutils.overrideAttrs {
        doCheck = false;
      };
    };
  };
}
