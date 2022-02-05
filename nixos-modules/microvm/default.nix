self:
{
  imports = [
    ./squashfs.nix
    ./options.nix
    ./system.nix
  ] ++ map (hypervisor:
    ./hypervisor + "/${hypervisor}.nix"
  ) self.lib.hypervisors;

  nixpkgs.overlays = [
    self.overlay
  ];
}
