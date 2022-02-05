{ config, pkgs, ... }:

let
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
in {
  system.build.squashfs = pkgs.runCommandLocal "rootfs-${config.networking.hostName}.squashfs" {
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
    for d in $(cat ${pkgs.writeReferencesToFile config.system.build.toplevel}); do
      cp -a $d rootfs/nix/store
    done

    mksquashfs rootfs $out \
      -reproducible -all-root -4k-align
  '';
}
