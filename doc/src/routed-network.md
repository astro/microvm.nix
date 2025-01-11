# Routed network setup

## Motivation

In bridged setups the Virtual Machines share the same Ethernet
segment. A compromised VM still has raw network access, allowing it to
send a lot of funny packets that cause problems for other
VMs. Examples:

- Forging MAC addresses
- Running rogue DHCP servers
- ARP/NDP spoofing
- Meddling with link-local multicast

This can be avoided by unsharing the Ethernet segments, ie. removing
the bridge.

## Addressing

Compared to one Ethernet where we assign a large subnet like
`10.0.0.0/24`, we will now only deal with *Host Routes* where the
prefix length is `/32` for IPv4 and `/128` for IPv6. Note that by
doing this we no longer lose precious space to a subnet's network and
broadcast addresses.

## Host configuration

Using systemd-networkd, a VM's tap interface is configured with static
addresses and the corresponding host routes. We do this for up to
`maxVMs`. Increasing this number will create as many `.network`
configuration files, so it's relatively cheap.

```nix
{ lib, ... }:

let
  maxVMs = 64;

in
{
  networking.useNetworkd = true;

  systemd.network.networks = builtins.listToAttrs (
    map (index: {
      name = "30-vm${toString index}";
      value = {
        matchConfig.Name = "vm${toString index}";
        # Host's addresses
        address = [
          "10.0.0.0/32"
          "fec0::/128"
        ];
        # Setup routes to the VM
        routes = [ {
          Destination = "10.0.0.${toString index}/32";
        } {
          Destination = "fec0::${lib.toHexString index}/128";
        } ];
        # Enable routing
        networkConfig = {
          IPv4Forwarding = true;
          IPv6Forwarding = true;
        };
      };
    }) (lib.genList (i: i + 1) maxVMs)
  );
}
```

## NAT

For NAT configuration on the host we're not going to specify each
potential tap interface. That would create a lot of firewall rules. To
avoid this additional complexity, use a single subnet that matches all
your VMs' addresses:

```nix
{
  networking.nat = {
    enable = true;
    internalIPs = [ "10.0.0.0/24" ];
    # Change this to the interface with upstream Internet access
    externalInterface = "enp0s3";
  };
}
```

# Virtual Machine configuration

We no longer rely on DHCP for this non-standard setup. To produce IPv4
and IPv6 addresses let's assign a number `index` to each MicroVM. Make
sure that this number is **not reused** by two VMs!

We suggest creating some sort of central configuration file that
contains each VM's network `index` in one place. That should make
reuses obvious. If that list becomes too long, write a NixOS
assertion!

```nix
{ lib, ... }:

let
  # Change this by VM!
  index = 5;

  mac = "00:00:00:00:00:01";

in
{
  microvm.interfaces = [ {
    id = "vm${toString index}";
    type = "tap";
    inherit mac;
  } ];

  networking.useNetworkd = true;

  systemd.network.networks."10-eth" = {
    matchConfig.MACAddress = mac;
    # Static IP configuration
    address = [
      "10.0.0.${toString index}/32"
      "fec0::${lib.toHexString index}/128"
    ];
    routes = [ {
      # A route to the host
      Destination = "10.0.0.0/32";
      GatewayOnLink = true;
    } {
      # Default route
      Destination = "0.0.0.0/0";
      Gateway = "10.0.0.0";
      GatewayOnLink = true;
    } {
      # Default route
      Destination = "::/0";
      Gateway = "fec0::";
      GatewayOnLink = true;
    } ];
    networkConfig = {
      # DNS servers no longer come from DHCP nor Router
      # Advertisements. Perhaps you want to change the defaults:
      DNS = [
        # Quad9.net
        "9.9.9.9"
        "149.112.112.112"
        "2620:fe::fe"
        "2620:fe::9"
      ];
    };
  };
}
```
