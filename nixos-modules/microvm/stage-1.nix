{ config, pkgs, lib, utils, ... }:
let
  inherit (config.microvm) storeOnBootDisk writableStoreOverlay;

  readOnlyStorePath =
    if storeOnBootDisk
    then "/nix/store"
    else "$targetRoot" + (
      # find share with host's /nix/store
      builtins.head (
        builtins.filter ({ source, ... }:
          source == "/nix/store"
        ) config.microvm.shares
      )
    ).mountPoint;
in {
  system.build.microvmStage1 = pkgs.substituteAll rec {
    src = ./stage-1-init.sh;

    shell = "${extraUtils}/bin/ash";
    isExecutable = true;
    inherit (config.system.build) extraUtils earlyMountScript;
    checkJournalingFS = 1;
    fsInfo =
      let f = fs: [ fs.mountPoint (if fs.device != null then fs.device else "/dev/disk/by-label/${fs.label}") fs.fsType (builtins.concatStringsSep "," fs.options) ];
      in pkgs.writeText "initrd-fsinfo" (builtins.concatStringsSep "\n" (builtins.concatMap f (builtins.filter utils.fsNeededForBoot (builtins.attrValues config.fileSystems))));
    postMountCommands =
      ''
        # Mark this as a NixOS machine.
        mkdir -p $targetRoot/etc
        echo -n > $targetRoot/etc/NIXOS

        # Fix the permissions on /tmp.
        chmod 1777 $targetRoot/tmp

        mkdir -p $targetRoot/boot

        ${lib.optionalString (writableStoreOverlay != null) ''
          echo "mounting overlay filesystem on /nix/store..."
          mkdir -p -m 0755 \
            $targetRoot/${writableStoreOverlay}/store \
            $targetRoot/${writableStoreOverlay}/work \
            $targetRoot/nix/store
          mount -t overlay overlay $targetRoot/nix/store \
            -o lowerdir=${readOnlyStorePath},upperdir=$targetRoot/${writableStoreOverlay}/store,workdir=$targetRoot/${writableStoreOverlay}/work || fail
        ''}
      '';
  };
  boot.postBootCommands = lib.optionalString (writableStoreOverlay != null) ''
    if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
      ${config.nix.package.out}/bin/nix-store --load-db < ''${BASH_REMATCH[1]}
    else
      echo "Error: no registration info passed on cmdline"
    fi
  '';

  microvm.kernelParams = [
    "root=/dev/vda" "ro"
    # stage1
    "init=/init"
    "devtmpfs.mount=0"
    # stage2
    "stage2init=${config.system.build.toplevel}/init"
    "boot.panic_on_fail" # "boot.shell_on_fail"
  ] ++ config.boot.kernelParams;

  fileSystems."/" = {
    device = "rootfs";
    fsType = "tmpfs";
    options = [ "size=50%,mode=0755" ];
  };
}
