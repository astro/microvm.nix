{ config, lib, pkgs, ... }:

let
  self-lib = import ../../lib {
    nixpkgs-lib = lib;
  };

  squashfs = self-lib.buildSquashfs {
    inherit config pkgs;
  };
in {
  system.build.squashfs = squashfs;

  microvm.kernelParams = [
    "regInfo=${squashfs.passthru.regInfo}/registration"
  ];
}
