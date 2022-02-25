self:
{
  imports = [
    ./squashfs.nix
    ./stage-1.nix
    ./options.nix
    ./system.nix
  ] ++ map (hypervisor:
    ./hypervisor + "/${hypervisor}.nix"
  ) self.lib.hypervisors;

  nixpkgs.overlays = [
    self.overlay
  ];
}
