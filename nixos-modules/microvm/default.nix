self:
{
  imports = [
    ./squashfs.nix
    ./options.nix
    ./system.nix
    ./hypervisor/qemu.nix
    ./hypervisor/cloud-hypervisor.nix
    ./hypervisor/firecracker.nix
    ./hypervisor/crosvm.nix
    ./hypervisor/kvmtool.nix
  ];

  nixpkgs.overlays = [
    self.overlay
  ];
}
