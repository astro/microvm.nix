self:
{ config, lib, pkgs, ... }:
{
  imports = [
    ./root-disk.nix
    ./options.nix
    ./asserts.nix
    ./system.nix
    ./mounts.nix
    ./graphics.nix
  ];

  config = {
    microvm.runner = lib.genAttrs self.lib.hypervisors (hypervisor:
      self.lib.buildRunner {
        inherit pkgs;
        microvmConfig = {
          inherit (config.networking) hostName;
          inherit hypervisor;
        } // config.microvm;
        inherit (config.boot.kernelPackages) kernel;
        inherit (config.system.build) toplevel;
        bootDisk = config.microvm.bootDisk;
      }
    );
  };
}
