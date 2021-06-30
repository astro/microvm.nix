{ modulesPath, writablePaths, config, microvm, ... }@args:
let
  lib = import ../lib {
    nixpkgs-lib = args.lib;
  };
in
{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];

  systemd.services.nix-daemon.enable = false;
  systemd.sockets.nix-daemon.enable = false;

  boot.loader.grub.enable = false;
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
  ) // (
    # Volumes
    builtins.foldl' (result: { mountpoint, device, fsType ? lib.defaultFsType, ... }: result // {
      "${mountpoint}" = {
        inherit device fsType;
      };
    }) {} (lib.withDriveLetters 1 microvm.volumes)
  );
}
