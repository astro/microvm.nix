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
  boot.kernelPackages = pkgs.linuxPackages_latest.extend (_self: super: {
    kernel = pkgs.microvm-kernel;
  });

  fileSystems."/" = {
    device = "/dev/vda";
    fsType = "squashfs";
    options = [ "ro" ];
  };
  # microvm.volumes = [ {
  #   mountPoint = "/";
  #   fsType = "squashfs";
  #   options = [ "ro" ];
  # } ];

  boot.specialFileSystems = (
    # writablePaths
    builtins.foldl' (result: path: result // {
      "${path}" = {
        device = path;
        fsType = "tmpfs";
      };
    }) {} rootImage.passthru.writablePaths
  ) // (
    # Volumes
    builtins.foldl' (result: { mountPoint, letter, fsType ? defaultFsType, ... }: result // {
      "${mountPoint}" = {
        inherit fsType;
        device = "/dev/vd${letter}";
      };
    }) {} (withDriveLetters 1 config.microvm.volumes)
  ) // (
    # Shares
    builtins.foldl' (result: { mountpoint, tag, ... }: result // {
      "${mountpoint}" = {
        device = tag;
        fsType = "virtiofs";
      };
    }) {} config.microvm.shares
  );
}
