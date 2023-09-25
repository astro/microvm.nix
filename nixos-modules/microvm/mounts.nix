{ config, lib, ... }:

let
  inherit (config.microvm) storeDiskType storeOnDisk writableStoreOverlay;

  inherit (import ../../lib {
    nixpkgs-lib = lib;
  }) defaultFsType withDriveLetters;

  hostStore = builtins.head (
    builtins.filter ({ source, ... }:
      source == "/nix/store"
    ) config.microvm.shares
  );

  roStore =
    if storeOnDisk
    then "/nix/.ro-store"
    else hostStore.mountPoint;

  roStoreDisk =
    if storeOnDisk
    then
      if storeDiskType == "erofs"
      # erofs supports filesystem labels
      then "/dev/disk/by-label/nix-store"
      else "/dev/vda"
    else throw "No disk letter when /nix/store is not in disk";

in
lib.mkIf config.microvm.guest.enable {
  fileSystems = lib.mkMerge [ (
    # built-in read-only store without overlay
    lib.optionalAttrs (
      storeOnDisk &&
      writableStoreOverlay == null
    ) {
      "/nix/store" = {
        device = roStoreDisk;
        fsType = storeDiskType;
        options = [ "x-systemd.after=systemd-modules-load.service" ];
        neededForBoot = true;
      };
    }
  ) (
    # host store is mounted somewhere else,
    # bind-mount to the proper place
    lib.optionalAttrs (
      !storeOnDisk &&
      config.microvm.writableStoreOverlay == null &&
      hostStore.mountPoint != "/nix/store"
    ) {
      "/nix/store" = {
        device = hostStore.mountPoint;
        options = [ "bind" ];
        neededForBoot = true;
      };
    }
  ) (
    # built-in read-only store for the overlay
    lib.optionalAttrs (
      storeOnDisk &&
      writableStoreOverlay != null
    ) {
      "/nix/.ro-store" = {
        device = roStoreDisk;
        fsType = storeDiskType;
        options = [ "x-systemd.after=systemd-modules-load.service" ];
        neededForBoot = true;
      };
    }
  ) (
    # mount store with writable overlay
    lib.optionalAttrs (writableStoreOverlay != null) {
      "/nix/store" = {
        device = "overlay";
        fsType = "overlay";
        neededForBoot = true;
        options = [
          "lowerdir=${roStore}"
          "upperdir=${writableStoreOverlay}/store"
          "workdir=${writableStoreOverlay}/work"
        ];
        depends = [ roStore writableStoreOverlay ];
      };
    }
  ) {
    # a tmpfs / by default. can be overwritten.
    "/" = lib.mkDefault {
      device = "rootfs";
      fsType = "tmpfs";
      options = [ "size=50%,mode=0755" ];
      neededForBoot = true;
    };
  } (
    # Volumes
    builtins.foldl' (result: { mountPoint, letter, fsType ? defaultFsType, ... }:
      result // lib.optionalAttrs (mountPoint != null) {
        "${mountPoint}" = {
          inherit fsType;
          device = "/dev/vd${letter}";
          neededForBoot = mountPoint == config.microvm.writableStoreOverlay;
        };
      }) {} (withDriveLetters config.microvm)
  ) (
    # 9p/virtiofs Shares
    builtins.foldl' (result: { mountPoint, tag, proto, source, ... }: result // {
      "${mountPoint}" = {
        device = tag;
        fsType = proto;
        options = {
          "virtiofs" = [ "defaults" "x-systemd.after=systemd-modules-load.service" ];
          "9p" = [ "trans=virtio" "version=9p2000.L"  "msize=65536" ];
        }.${proto};
        neededForBoot = source == "/nix/store" ||
          mountPoint == config.microvm.writableStoreOverlay;
      };
    }) {} config.microvm.shares
  ) ];

  # boot.initrd.systemd patchups copied from <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
  boot.initrd.systemd = lib.mkIf (config.boot.initrd.systemd.enable && writableStoreOverlay != null) {
    mounts = [ {
      where = "/sysroot/nix/store";
      what = "overlay";
      type = "overlay";
      options = builtins.concatStringsSep "," [
        "lowerdir=/sysroot${roStore}"
        "upperdir=/sysroot${writableStoreOverlay}/store"
        "workdir=/sysroot${writableStoreOverlay}/work"
      ];
      wantedBy = [ "initrd-fs.target" ];
      before = [ "initrd-fs.target" ];
      requires = [ "rw-store.service" ];
      after = [ "rw-store.service" ];
      unitConfig.RequiresMountsFor = "${roStore}";
    } ];
    services.rw-store = {
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = "/sysroot${writableStoreOverlay}";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/bin/mkdir -p -m 0755 /sysroot${writableStoreOverlay}/store /sysroot${writableStoreOverlay}/work /sysroot/nix/store";
      };
    };
  };
}
