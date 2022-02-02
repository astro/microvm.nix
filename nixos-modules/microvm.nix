{ modulesPath, writablePaths, pkgs, microvm, ... }@args:
let
  lib = import ../lib {
    nixpkgs-lib = args.lib;
  };
in
{
  # WORKS: system.build.microvm = lib.makeMicrovm microvm;

  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];

  systemd.services.nix-daemon.enable = false;
  systemd.sockets.nix-daemon.enable = false;

  boot.loader.grub.enable = false;
  boot.kernelPackages = pkgs.linuxPackages_latest.extend (_self: super: {
    kernel = pkgs.microvm-kernel;
  });

  fileSystems."/" = {
    device = "/dev/vda";
    fsType = "ext4";
    options = [ "ro" ];
  };

  boot.specialFileSystems = (
    # writablePaths
    builtins.foldl' (result: path: result // {
      "${path}" = {
        device = path;
        fsType = "tmpfs";
      };
    }) {} writablePaths
  ) // (args.lib.optionalAttrs (microvm ? volumes) (
    # Volumes
    builtins.foldl' (result: { mountpoint, device, fsType ? lib.defaultFsType, ... }: result // {
      "${mountpoint}" = {
        inherit device fsType;
      };
    }) {} (lib.withDriveLetters 1 microvm.volumes)
  )) // (args.lib.optionalAttrs (microvm ? shares) (
    # Shares
    builtins.foldl' (result: { mountpoint, tag, ... }: result // {
      "${mountpoint}" = {
        device = tag;
        fsType = "virtiofs";
      };
    }) {} microvm.shares
  ));
}
