# A simple network setup

While networking infrastructure is out of scope for the **microvm.nix**
flake, here is some guidance for providing the MicroVMs on your NixOS
machine with internet access.

Because we already use systemd for MicroVM startup, let's pick
`systemd-networkd`:
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

This configuration will hand out IP addresses to clients on the
bridge. In practise, better leave out the DHCP server and its state by
opting for declarative, versioned configuration instead.

Last, the TAP interfaces of MicroVMs shall be attached to this central
bridge. Make sure your `matchConfig` matches just the interfaces you
want!
```nix
systemd.network = {
  networks."11-microvm" = {
    matchConfig.Name = "vm-*";
    # Attach to the bridge that was configured above
    networkConfig.Bridge = "microvm";
  };
};
```

## Provide Internet Access with NAT

IPv4 addresses are exhausted. It is a very common case that you get
one public IPv4 address for your machine. The solution is to route
your internal virtual machines with *Network Address Translation*.

You might not get a dedicated /64 IPv6 prefix to route to your
MicroVMs. NAT works for this address family, too!

```nix
networking.nat = {
  enable = true;
  enableIPv6 = true;
  # Change this to the interface with upstream Internet access
  externalInterface = "eth0";
  internalInterfaces = [ "microvm" ];
};
```

Check out
[`networking.nat.forwardPorts`](https://search.nixos.org/options?channel=unstable&show=networking.nat.forwardPorts&query=networking.nat.forwardPorts)
to make your MicroVM's services available to networks outside your
host!

## Port forwarding

Isolating your public Internet services is a great use-case for
virtualization. But how does traffic get to you when your MicroVMs
have private IP addresses behind NAT?

NixOS has got you covered with the `networking.nat.forwardPorts`
option! This example forwards TCP ports 80 (HTTP) and 443 (HTTPS) to
other hosts:

```nix
networking.nat = {
  enable = true;
  forwardPorts = [ {
    proto = "tcp";
    sourcePort = 80;
    destination = my-addresses.http-reverse-proxy.ip4;
  } {
    proto = "tcp";
    sourcePort = 443;
    destination = my-addresses.https-reverse-proxy.ip4;
  } ];
};
```
