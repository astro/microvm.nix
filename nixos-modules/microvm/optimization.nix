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
{
  options.microvm.optimize = {
    enable = lib.mkOption {
      description = lib.mdDoc ''
        Enables some optimizations to closure size and startup time:
          - disables X libraries for non-graphical VMs
          - defaults documentation to off
          - defaults to using systemd in initrd
          - builds qemu without graphics or sound for non-graphical qemu VMs

        This takes a few hundred MB off the closure size, including qemu,
        allowing for putting microvms inside Docker containers.

        May cause more build time by e.g. rebuilding qemu.
      '';

      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf (cfg.guest.enable && cfg.optimize.enable) {
    # Avoids X deps in closure due to dbus dependencies
    environment.noXlibs = lib.mkIf (!cfg.graphics.enable) (lib.mkDefault true);

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

    # Exclude switch-to-confguration.pl from toplevel.
    system = lib.optionalAttrs (options.system ? switch && !canSwitchViaSsh) {
      switch.enable = lib.mkDefault false;
    };
  };
}
