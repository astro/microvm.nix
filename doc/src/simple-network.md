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

To make your MicroVM reachable, the host will place its Ethernet port (`eno1`)
on a bridge (`br0`). This bridge will have the MicroVM's TAP interface attached
to it - directly placing the MicroVM on your local network.

Note that the addresses provided below are examples and you must adjust these
for your network settings. Also note that the `eno1` must be attached to the
bridge with the `vm-*` TAP interfaces that you will specify in the MicroVM
definition.

```nix
systemd.network.enable = true;

systemd.network.networks."10-lan" = {
  matchConfig.Name = ["eno1" "vm-*"];
  networkConfig = {
    Bridge = "br0";
  };
};

systemd.network.netdevs."br0" = {
  netdevConfig = {
    Name = "br0";
    Kind = "bridge";
  };
};

systemd.network.networks."10-lan-bridge" = {
  matchConfig.Name = "br0";
  networkConfig = {
    Address = ["192.168.1.2/24" "2001:db8::a/64"];
    Gateway = "192.168.1.1";
    DNS = ["192.168.1.1"];
    IPv6AcceptRA = true;
  };
  linkConfig.RequiredForOnline = "routable";
};
```

Now that the host is configured, you can define a MicroVM to have a static IP
address with:

```nix
microvm = {
  #...add additional MicroVM configuration here
  interfaces = [
    {
      type = "tap";
      id = "vm-test1";
      mac = "02:00:00:00:00:01";
    }
  ];
};

systemd.network.enable = true;

systemd.network.networks."20-lan" = {
  matchConfig.Type = "ether";
  networkConfig = {
    Address = ["192.168.1.3/24" "2001:db8::b/64"];
    Gateway = "192.168.1.1";
    DNS = ["192.168.1.1"];
    IPv6AcceptRA = true;
    DHCP = "no";
  };
};
```

