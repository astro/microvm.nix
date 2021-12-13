{ modulesPath, writablePaths, pkgs, microvm, ... }@args:
let
  lib = import ../lib {
    nixpkgs-lib = args.lib;
  };
in
{
  # WORKS: system.build.microvm = lib.makeMicrovm microvm;

  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];

  systemd.services.nix-daemon.enable = false;
  systemd.sockets.nix-daemon.enable = false;

  boot.loader.grub.enable = false;
  boot.kernelPackages = pkgs.linuxPackages_latest.extend (_self: super: {
    kernel = super.kernel.override {
      extraConfig = ''
        PVH y
        PARAVIRT y
        PARAVIRT_TIME_ACCOUNTING y
        HAVE_VIRT_CPU_ACCOUNTING_GEN y
        VIRT_DRIVERS y
        VIRTIO_BLK y
        FUSE_FS y
        VIRTIO_FS y
        #FS_DAX y
        #FUSE_DAX y
        BLK_MQ_VIRTIO y
        VIRTIO_NET y
        VIRTIO_BALLOON y
        VIRTIO_CONSOLE y
        VIRTIO_MMIO y
        VIRTIO_MMIO_CMDLINE_DEVICES y
        VIRTIO_PCI y
        VIRTIO_PCI_LIB y
        VIRTIO_VSOCKETS m
        EXT4_FS y
        SQUASHFS y
        SQUASHFS_XZ y

        # for Firecracker SendCtrlAltDel
        SERIO_I8042 y
        KEYBOARD_ATKBD y
        # for Cloud-Hypervisor shutdown
        ACPI_BUTTON y
        EXPERT y
        ACPI_REDUCED_HARDWARE_ONLY y
      '';
    };
  });

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
  ) // (args.lib.optionalAttrs (microvm ? volumes) (
    # Volumes
    builtins.foldl' (result: { mountpoint, device, fsType ? lib.defaultFsType, ... }: result // {
      "${mountpoint}" = {
        inherit device fsType;
      };
    }) {} (lib.withDriveLetters 1 microvm.volumes)
  )) // (args.lib.optionalAttrs (microvm ? shares) (
    # Shares
    builtins.foldl' (result: { mountpoint, tag, ... }: result // {
      "${mountpoint}" = {
        device = tag;
        fsType = "virtiofs";
      };
    }) {} microvm.shares
  ));
}
