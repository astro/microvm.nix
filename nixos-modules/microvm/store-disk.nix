{ config, lib, pkgs, ... }:

let
  regInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };

  kernelAtLeast = lib.versionAtLeast config.boot.kernelPackages.kernel.version;

  erofsFlags = builtins.concatStringsSep " " (
    [ "-zlz4hc" "--force-uid=0" "--force-gid=0" ]
    # ++
    # lib.optional (kernelAtLeast "5.13") "-C1048576"
    ++
    lib.optional (kernelAtLeast "5.16") "-Eztailpacking"
    ++
    lib.optionals (kernelAtLeast "6.1") [
      "-Efragments"
      # "-Ededupe"
    ]
  );
in
{
  options.microvm = with lib; {
    storeDiskType = mkOption {
      type = types.enum [ "squashfs" "erofs" ];
      description = ''
        Boot disk file system type: squashfs is smaller, erofs is supposed to be faster.
      '';
    };

    storeDisk = mkOption {
      type = types.path;
      description = ''
        Generated
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.microvm.guest.enable && config.microvm.storeOnDisk) {
      # nixos/modules/profiles/hardened.nix forbids erofs.
      # HACK: Other NixOS modules populate
      # config.boot.blacklistedKernelModules depending on the boot
      # filesystems, so checking on that directly would result in an
      # infinite recursion.
      microvm.storeDiskType = lib.mkDefault (
        if config.security.virtualisation.flushL1DataCache == "always"
        then "squashfs"
        else "erofs"
      );
      boot.initrd.availableKernelModules = [
        config.microvm.storeDiskType
      ];

      microvm.storeDisk = pkgs.runCommandLocal "microvm-store-disk.${config.microvm.storeDiskType}" {
        nativeBuildInputs = with pkgs.buildPackages; [ {
          squashfs = [ squashfs-tools-ng ];
          erofs = [ erofs-utils ];
        }.${config.microvm.storeDiskType} ];
        passthru = {
          inherit regInfo;
        };
      } ''
        echo Copying a /nix/store
        mkdir store
        for d in $(sort -u ${
          lib.concatMapStringsSep " " pkgs.writeReferencesToFile (
            lib.optionals config.microvm.storeOnDisk (
              [ config.system.build.toplevel ]
              ++
              lib.optional config.nix.enable regInfo
            )
          )
        }); do
          cp -a $d store
        done

        echo Creating a ${config.microvm.storeDiskType}
        ${{
          squashfs = "gensquashfs -D store --all-root -c zstd -q $out";
          erofs = "mkfs.erofs ${erofsFlags} -L nix-store --mount-point=/nix/store $out store";
        }.${config.microvm.storeDiskType}}
      '';
    })

    (lib.mkIf (config.microvm.guest.enable && config.nix.enable) {
      microvm.kernelParams = [
        "regInfo=${regInfo}/registration"
      ];
      boot.postBootCommands = ''
        if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
          ${config.nix.package.out}/bin/nix-store --load-db < ''${BASH_REMATCH[1]}
        fi
      '';
    })
  ];
}
