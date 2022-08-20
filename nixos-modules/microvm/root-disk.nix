{ config, lib, pkgs, ... }:

let
  self-lib = import ../../lib {
    nixpkgs-lib = lib;
  };
in {
  options.microvm = with lib; {
    bootDiskType = mkOption {
      type = types.enum [ "squashfs" "erofs" ];
      default = "suqashfs";
      description = ''
        Boot disk file system type: squashfs is smaller, erofs is supposed to be faster.
      '';
    };

    bootDisk = mkOption {
      type = types.package;
      default = {
        inherit (config.system.build) squashfs erofs;
      }.${config.microvm.bootDiskType};
    };
  };

  config = {
    system.build.squashfs = self-lib.buildSquashfs {
      inherit config pkgs;
    };
    system.build.erofs = self-lib.buildErofs {
      inherit config pkgs;
    };

    microvm.kernelParams = [
      "regInfo=${config.microvm.bootDisk.passthru.regInfo}/registration"
    ];
  };
}
