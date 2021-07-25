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
                }:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in                
    pkgs.runCommandLocal "rootfs-${hostName}.squashfs" {
      buildInputs = [ pkgs.squashfsTools ];
      passthru = {
        inherit writablePaths;
      };
    } ''
      mkdir -p ${builtins.concatStringsSep " " (
        map (path:
          "rootfs${path}"
        ) (writablePaths ++ [ "/dev" "/nix/var/nix/gcroots" "/proc" "/run" "/sys" "/nix/store" ])
      )}
      for d in $(cat ${pkgs.writeReferencesToFile nixos.config.system.build.toplevel}); do
        cp -a $d rootfs/nix/store
      done

      mksquashfs rootfs $out \
        -comp xz -reproducible -all-root -4k-align
    '';
}
