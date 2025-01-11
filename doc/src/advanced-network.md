# Advanced network setup

Renting a server in a datacenter usually gets you one IP address. You
must not bridge your local VM traffic together with the physical
Ethernet uplink port. Instead, setup a host-internal bridge for the
Virtual Machines, and provide them with Internet through NAT just like
your plastic ADSL router at home.

## A bridge to link TAP interfaces

Instead of placing MicroVMs directly on a LAN, one can also use a TAP
interface to get a virtual Ethernet interface on the host. Although it
is possible to [assign individual IP
configuration](./routed-network.md) to these individual interfaces,
let us avoid the additional configuration effort and create a bridge
instead:

```nix
systemd.network.netdevs."10-microvm".netdevConfig = {
  Kind = "bridge";
  Name = "microvm";
};
systemd.network.networks."10-microvm" = {
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

# Allow inbound traffic for the DHCP server
networking.firewall.allowedUDPPorts = [ 67 ];
```

This configuration will hand out IP addresses to clients on the
bridge. In practise, better leave out the DHCP server and its state by
opting for declarative, versioned configuration instead.

Last, the TAP interfaces of MicroVMs shall be attached to this central
bridge. Make sure your `matchConfig` matches just the interfaces you
want!
```nix
systemd.network.networks."11-microvm" = {
  matchConfig.Name = "vm-*";
  # Attach to the bridge that was configured above
  networkConfig.Bridge = "microvm";
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
  # NAT66 exists and works. But if you have a proper subnet in
  # 2000::/3 you should route that and remove this setting:
  enableIPv6 = true;

  # Change this to the interface with upstream Internet access
  externalInterface = "eth0";
  # The bridge where you want to provide Internet access
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
