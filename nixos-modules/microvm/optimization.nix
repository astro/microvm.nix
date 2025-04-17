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

  boot = {
    initrd.systemd = {
      # Use systemd initrd for startup speed.
      # TODO: error mounting /nix/store on crosvm, kvmtool
      enable = lib.mkDefault (
        builtins.elem cfg.hypervisor [
          "qemu"
          "cloud-hypervisor"
          "firecracker"
          "stratovirt"
        ]);
      tpm2.enable = lib.mkDefault false;
    };
    swraid.enable = false;
  };

  nixpkgs.overlays = [
    (final: prev: {
      stratovirt = prev.stratovirt.override { gtk3 = null; };
    })
  ];

  # networkd is used due to some strange startup time issues with nixos's
  # homegrown dhcp implementation
  networking.useNetworkd = lib.mkDefault true;

  systemd = {
    # Due to a bug in systemd-networkd: https://github.com/systemd/systemd/issues/29388
    # we cannot use systemd-networkd-wait-online.
    network.wait-online.enable = lib.mkDefault false;
    tpm2.enable = lib.mkDefault false;
  };

  # Exclude switch-to-configuration.pl from toplevel.
  system = lib.optionalAttrs (options.system ? switch && !canSwitchViaSsh) {
    switch.enable = lib.mkDefault false;
  };
}
