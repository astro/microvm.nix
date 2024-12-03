{ config, lib, pkgs, ... }:

let
  inherit (config.networking) hostName;

  interfacesByType = wantedType:
    builtins.filter ({ type, ... }: type == wantedType)
      config.microvm.interfaces;

  tapInterfaces = interfacesByType "tap";
  macvtapInterfaces = interfacesByType "macvtap";

  tapFlags = lib.concatStringsSep " " (
    [ "vnet_hdr" ] ++
    lib.optional config.microvm.declaredRunner.passthru.tapMultiQueue "multi_queue"
  );

  # TODO: don't hardcode but obtain from host config
  user = "microvm";
  group = "kvm";
in
{
  microvm.binScripts = lib.mkMerge [ (
    lib.mkIf (tapInterfaces != []) {
      tap-up = ''
        set -eou pipefail
      '' + lib.concatMapStrings ({ id, mac, ... }: ''
        if [ -e /sys/class/net/${id} ]; then
          ${pkgs.iproute2}/bin/ip tuntap del name '${id}' mode tap ${tapFlags}
        fi

        ${pkgs.iproute2}/bin/ip tuntap add name '${id}' mode tap user '${user}' ${tapFlags}
      '') tapInterfaces;

      tap-down = ''
        set -ou pipefail
      '' + lib.concatMapStrings ({ id, mac, ... }: ''
        ${pkgs.iproute2}/bin/ip tuntap del name '${id}' mode tap ${tapFlags}
      '') tapInterfaces;
    }
  ) (
    lib.mkIf (macvtapInterfaces != []) {
      macvtap-up = ''
        set -eou pipefail
      '' + lib.concatMapStrings ({ id, mac, macvtap, ... }: ''
        if [ -e /sys/class/net/${id} ]; then
          ${pkgs.iproute2}/bin/ip link del name '${id}'
        fi
        ${pkgs.iproute2}/bin/ip link add link '${macvtap.link}' name '${id}' address '${mac}' type macvtap '${macvtap.mode}'
        ${pkgs.iproute2}/bin/ip link set '${id}' allmulticast on
        echo 1 > "/proc/sys/net/ipv6/conf/${id}/disable_ipv6"
        ${pkgs.iproute2}/bin/ip link set '${id}' up
        ${pkgs.coreutils-full}/bin/chown '${user}:${group}' /dev/tap$(< "/sys/class/net/${id}/ifindex")
      '') macvtapInterfaces;

      macvtap-down = ''
        set -ou pipefail
      '' + lib.concatMapStrings ({ id, ... }: ''
        ${pkgs.iproute2}/bin/ip link del name '${id}'
      '') macvtapInterfaces;
    }
  ) ];
}
