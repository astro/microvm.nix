# Closure size and startup time optimization for disposable use-cases
{ config, lib, pkgs, ... }:
let cfg = config.microvm;
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
    environment.noXlibs = lib.mkIf (!cfg.graphics.enable) true;

    # The docs are pretty chonky
    documentation.enable = lib.mkDefault false;

    # Use systemd initrd for startup speed
    boot.initrd.systemd.enable = lib.mkDefault true;

    # networkd is used due to some strange startup time issues with nixos's
    # homegrown dhcp implementation
    networking.useNetworkd = lib.mkDefault true;
    # Due to a bug in systemd-networkd: https://github.com/systemd/systemd/issues/29388
    # we cannot use systemd-networkd-wait-online.
    systemd.network.wait-online.enable = false;
  };
}
