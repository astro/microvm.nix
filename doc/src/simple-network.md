# A simple network setup

While your network setup is out of scope for the **microvm.nix**
flake, here is a simple guide for getting the MicroVMs on your server
networked.

Be aware that we dictate `systemd-networkd` on your server for maximum flexibility:
```nix
networking.useNetworkd = true;
```

## A bridge to link TAP interfaces

To make your MicroVM reachable, use a TAP interface to get a virtual
Ethernet interface on the host. Although it is possible to assign
individual IP configuration to these individual interfaces, let us
avoid the additional configuration effort and create a bridge instead:
```nix
systemd.network = {
  netdevs."10-microvm".netdevConfig = {
    Kind = "bridge";
    Name = "microvm";
  };
  networks."10-microvm" = {
    matchConfig.Name = "microvm";
    networkConfig = {
      DHCPServer = true;
      IPv6SendRA = true;
    };
    addresses = [ {
      addressConfig.Address = "10.0.0.1/24";
    } {
      addressConfig.Address = "fd12:3456:789a::1/64";
    } ];
    ipv6Prefixes = [ {
      ipv6PrefixConfig.Prefix = "fd12:3456:789a::/64";
    } ];
  };
};
```

Better leave out the DHCP server and opt for static configuration
instead if you rely on stable IPv4 addresses.

Last, the TAP interfaces shall be attached to this central bridge. Make
sure your `matchConfig` matches just the interfaces you want!
```nix
systemd.network = {
  networks."11-microvm" = {
    matchConfig.Name = "vm-*";
    networkConfig.Bridge = "microvm";
  };
};
```

## Provide Internet Access with NAT

IPv4 addresses are exhausted. In some server environments you may not
get a dedicated /64 IPv6 prefix to route to your MicroVMs. *Network
Address Translation* to the rescue!
```nix
networking.nat = {
  enable = true;
  enableIPv6 = true;
  externalInterface = "eth0";
  internalInterfaces = [ "microvm" ];
};
```

Check out
[`networking.nat.forwardPorts`](https://search.nixos.org/options?channel=unstable&show=networking.nat.forwardPorts&query=networking.nat.forwardPorts)
to make your MicroVM's services available to networks outside your
host!
