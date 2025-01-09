{ config, lib, pkgs, ... }:

let
  regInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };

  kernelAtLeast = lib.versionAtLeast config.boot.kernelPackages.kernel.version;

  erofs-utils =
    # Are any extended options specified?
    if lib.any (with lib; flip elem ["-Ededupe" "-Efragments"]) config.microvm.storeDiskErofsFlags
    then
      # If extended options are present,
      # stick to the single-threaded erofs-utils
      # to not scare anyone with warning messages.
      pkgs.buildPackages.erofs-utils
    else
      # If no extended options are configured,
      # rebuild mkfs.erofs with multi-threading.
      pkgs.buildPackages.erofs-utils.overrideAttrs (attrs: {
        configureFlags = attrs.configureFlags ++ [
          "--enable-multithreading"
        ];
      });

  erofsFlags = builtins.concatStringsSep " " config.microvm.storeDiskErofsFlags;
  squashfsFlags = builtins.concatStringsSep " " config.microvm.storeDiskSquashfsFlags;

  writeClosure = pkgs.writeClosure or pkgs.writeReferencesToFile;

  storeDiskContents = writeClosure (
    [ config.system.build.toplevel ]
    ++
    lib.optional config.nix.enable regInfo
  );

in
{
  options.microvm.storeDisk = with lib; mkOption {
    type = types.path;
    description = ''
      Generated
    '';
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
        nativeBuildInputs = [
          pkgs.buildPackages.time
          pkgs.buildPackages.bubblewrap
          {
            squashfs = [ pkgs.buildPackages.squashfs-tools-ng ];
            erofs = [ erofs-utils ];
          }.${config.microvm.storeDiskType}
        ];
        passthru = {
          inherit regInfo;
        };
      } ''
        mkdir store
        BWRAP_ARGS="--dev-bind / / --chdir $(pwd)"
        for d in $(sort -u ${storeDiskContents}); do
          BWRAP_ARGS="$BWRAP_ARGS --ro-bind $d $(pwd)/store/$(basename $d)"
        done

        echo Creating a ${config.microvm.storeDiskType}
        bwrap $BWRAP_ARGS -- time ${{
          squashfs = "gensquashfs ${squashfsFlags} -D store --all-root -q $out";
          erofs = "mkfs.erofs ${erofsFlags} -T 0 --all-root -L nix-store --mount-point=/nix/store $out store";
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
