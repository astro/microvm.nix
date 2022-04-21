# A simple network setup

While your network setup is out of scope for the **microvm.nix**
flake, here is a simple guide for getting the MicroVMs on your server
networked.

Be aware that we dictate `systemd-networkd` on your server for maximum flexibility:
```nix
networking.useNetworkd = true;
```

## A bridge to link TAP interfaces

To make your MicroVM available, use a TAP interface to get a virtual
network interface on the host to represent the Ethernet segment to
your network. It is possible to assign individual IP configuration to
these individual interfaces but that comes at some configuration
effort. Let networkd create a bridge instead:
```nix
systemd.network = {
  netdevs."10-microvm" = {
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

You better leave out the DHCP server and opt for static configuration
instead if you rely on stable IPv4 addresses.

Now the TAP interfaces must be attached to this central bridge. Make
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

Check out `networking.nat.forwardPorts` to make your MicroVM's
services available to networks outside your host!
