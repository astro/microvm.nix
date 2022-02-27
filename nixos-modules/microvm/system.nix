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

  boot.loader.grub.enable = false;
  boot.kernelPackages = pkgs.linuxPackages_latest.extend (_: _: {
    kernel = pkgs.microvm-kernel;
  });

  fileSystems = (
    # Volumes
    builtins.foldl' (result: { mountPoint, letter, fsType ? defaultFsType, ... }: result // {
      "${mountPoint}" = {
        inherit fsType;
        device = "/dev/vd${letter}";
        neededForBoot = mountPoint == config.microvm.writableStoreOverlay;
      };
    }) {} (withDriveLetters 1 config.microvm.volumes)
  ) // (
    # Shares
    builtins.foldl' (result: { mountPoint, tag, proto, source, ... }: result // {
      "${mountPoint}" = {
        device = tag;
        fsType = proto;
        options = {
          "virtiofs" = [];
          "9p" = [ "trans=virtio" "version=9p2000.L"  "msize=65536" ];
        }.${proto};
        neededForBoot = (
          source == "/nix/store" ||
          mountPoint == config.microvm.writableStoreOverlay
        );
      };
    }) {} config.microvm.shares
  ) // (
    if config.microvm.storeOnBootDisk
    then {
      "/nix/store" = {
        device = "//nix/store";
        options = [ "bind" ];
        neededForBoot = true;
      };
    } else if config.microvm.writableStoreOverlay == null
      then let
        hostStore = builtins.head (
          builtins.filter ({ source, ... }:
            source == "/nix/store"
          ) config.microvm.shares
        );
      in {
        "/nix/store" = {
          device = hostStore.mountPoint;
          options = [ "bind" ];
          neededForBoot = true;
        };
      }
      else {}
  );
}
