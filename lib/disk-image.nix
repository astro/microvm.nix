{ self, nixpkgs }:

rec {
  writablePaths = [
    "/bin"
    "/etc"
    "/home"
    "/nix/var"
    "/root"
    "/usr"
    "/var"
    "/tmp"
  ];

  mkDiskImage = { system
                , hostName
                , nixos
                , rootReserve ? "64M"
                }:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in                
    pkgs.runCommandLocal "rootfs-${hostName}.img" {
      buildInputs = [ pkgs.libguestfs-with-appliance ];
      passthru = {
        inherit writablePaths;
      };
    } ''
      mkdir -p ${builtins.concatStringsSep " " (
        map (path:
          "rootfs${path}"
        ) (writablePaths ++ [ "/dev" "/nix/var/nix/gcroots" "/proc" "/run" "/sys" ])
      )}

      cp -a --no-preserve=xattr --parents \
        $(cat ${pkgs.writeReferencesToFile nixos.config.system.build.toplevel}) \
        rootfs/
      virt-make-fs --size=+${rootReserve} --type=ext4 rootfs $out

      # add padding to sector size
      dd if=/dev/zero of=$out seek=$(($(stat -c %s $out) / 512 + 1)) count=1 bs=512
    '';
}
