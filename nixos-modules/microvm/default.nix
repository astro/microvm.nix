self:
{ config, lib, pkgs, ... }:
{
  imports = [
    ./squashfs.nix
    ./stage-1.nix
    ./options.nix
    ./system.nix
  ];

  nixpkgs.overlays = [
    self.overlay
  ];

  microvm.runner = lib.genAttrs self.lib.hypervisors (hypervisor:
    self.lib.buildRunner {
      inherit pkgs;
      microvmConfig = {
        inherit (config.networking) hostName;
        inherit hypervisor;
      } // config.microvm;
      inherit (config.boot.kernelPackages) kernel;
      inherit (config.system.build) toplevel;
      rootDisk = config.system.build.squashfs;
    }
  );
}
