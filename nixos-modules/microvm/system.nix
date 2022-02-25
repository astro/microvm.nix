{ modulesPath, pkgs, config, ... }@args:
let
  inherit (import ../../lib {
    nixpkgs-lib = args.lib;
  }) defaultFsType withDriveLetters;

  rootImage = config.system.build.squashfs;
in
{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];

  systemd.services.nix-daemon.enable = false;
  systemd.sockets.nix-daemon.enable = false;

  boot.loader.grub.enable = false;
  boot.kernelPackages = pkgs.linuxPackages_latest.extend (_: _: {
    kernel = pkgs.microvm-kernel;
  });

  boot.specialFileSystems = (
    # Volumes
    builtins.foldl' (result: { mountPoint, letter, fsType ? defaultFsType, ... }: result // {
      "${mountPoint}" = {
        inherit fsType;
        device = "/dev/vd${letter}";
      };
    }) {} (withDriveLetters 1 config.microvm.volumes)
  ) // (
    # Shares
    builtins.foldl' (result: { mountPoint, tag, ... }: result // {
      "${mountPoint}" = {
        device = tag;
        fsType = "virtiofs";
      };
    }) {} config.microvm.shares
  );
}
