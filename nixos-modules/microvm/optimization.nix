# Closure size and startup time optimization for disposable use-cases
{ config, options, lib, ... }:

let
  cfg = config.microvm;


  canSwitchViaSsh =
    config.services.openssh.enable &&
    # Is the /nix/store mounted from the host?
    builtins.any ({ source, ... }:
      source == "/nix/store"
    ) config.microvm.shares;

in
lib.mkIf (cfg.guest.enable && cfg.optimize.enable) {
  # The docs are pretty chonky
  documentation.enable = lib.mkDefault false;

  # Use systemd initrd for startup speed.
  # TODO: error mounting /nix/store on crosvm, kvmtool
  boot.initrd.systemd.enable = lib.mkDefault (
    builtins.elem cfg.hypervisor [
      "qemu"
      "cloud-hypervisor"
      "firecracker"
      "stratovirt"
    ]);

  nixpkgs.overlays = [
    (final: prev: {
      stratovirt = prev.stratovirt.override { gtk3 = null; };
    })
  ];

  # networkd is used due to some strange startup time issues with nixos's
  # homegrown dhcp implementation
  networking.useNetworkd = lib.mkDefault true;
  # Due to a bug in systemd-networkd: https://github.com/systemd/systemd/issues/29388
  # we cannot use systemd-networkd-wait-online.
  systemd.network.wait-online.enable = lib.mkDefault false;

  # Exclude switch-to-configuration.pl from toplevel.
  system = lib.optionalAttrs (options.system ? switch && !canSwitchViaSsh) {
    switch.enable = lib.mkDefault false;
  };
}
