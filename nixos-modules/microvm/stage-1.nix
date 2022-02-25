{ config, pkgs, lib, utils, ... }:
let
  empty = pkgs.runCommand "empty.d" {
    preferLocalBuild = true;
  } "mkdir $out";
  # TODO:
  # - hostStoreRO: share with source == "/nix/store"
  # - store writable overlay: share or volume
in {
  system.build.microvmStage1 = pkgs.substituteAll rec {
    src = ./stage-1-init.sh;

    shell = "${extraUtils}/bin/ash";
    isExecutable = true;
    inherit (config.system.build) extraUtils earlyMountScript;
    # inherit (config.microvm) storeOnBootDisk;
    storeOnBootDisk = if config.microvm.storeOnBootDisk then true else throw "not storeOnBootDisk";
    linkUnits = empty;
    udevRules = empty;
    inherit (config.boot.initrd) checkJournalingFS verbose;
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

        ${lib.optionalString config.microvm.writableStore ''
          echo "mounting overlay filesystem on /nix/store..."
          mkdir -p 0755 $targetRoot/nix/.rw-store/store $targetRoot/nix/.rw-store/work $targetRoot/nix/store
          mount -t overlay overlay $targetRoot/nix/store \
            -o lowerdir=$targetRoot/nix/.ro-store,upperdir=$targetRoot/nix/.rw-store/store,workdir=$targetRoot/nix/.rw-store/work || fail
        ''}
      '';
    # After booting, register the closure of the paths in
    # `virtualisation.additionalPaths' in the Nix database in the VM.  This
    # allows Nix operations to work in the VM.  The path to the
    # registration file is passed through the kernel command line to
    # allow `system.build.toplevel' to be included.  (If we had a direct
    # reference to ${regInfo} here, then we would get a cyclic
    # dependency.)
    postBootCommands =
      ''
        if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
          ${config.nix.package.out}/bin/nix-store --load-db < ''${BASH_REMATCH[1]}
        fi
      '';
  };

  boot.kernelParams = [
    "devtmps.mount=0"
  ];

  fileSystems."/" = {
    device = "rootfs";
    fsType = "tmpfs";
    options = [ "size=50%" ];
  };
}
