{ kernel, ... }:
kernel.override {
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
    NET_9P y
    NET_9P_VIRTIO y
    9P_FS y
    9P_FS_POSIX_ACL y
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
}
