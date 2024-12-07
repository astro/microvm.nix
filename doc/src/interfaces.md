# Network interfaces

Declare a MicroVM's virtual network interfaces like this in its NixOS
configuration:
```nix
{
  microvm.interfaces = [ {
    type = "tap";

    # interface name on the host
    id = "vm-a1";

    # Ethernet address of the MicroVM's interface, not the host's
    #
    # Locally administered have one of 2/6/A/E in the second nibble.
    mac = "02:00:00:00:00:01";
  } ];
}
```

## `type = "user"`

User-mode networking is only provided by qemu and kvmtool, providing
outgoing connectivity to your MicroVM without any further setup.

As kvmtool seems to lack a built-in DHCP server, additional static IP
configuration is necessary inside the MicroVM.

## `type = "tap"`

Use a virtual tuntap Ethernet interface. Its name is the value of
`id`.

Some Hypervisors may be able to automatically create these interfaces
when running as root, which we advise against. Instead, create the
interfaces before starting a MicroVM:

```bash
sudo ip tuntap add $IFACE_NAME mode tap user $USER
```

**Note:** add `multi_queue` to this command line if the VM is configured
with more than one CPU core.

When running MicroVMs through the `host` module, the tap network
interfaces are created through a systemd service dependency.

Extend the generated script in the guest configuration like this:

```nix
microvm.binScripts.tap-up = lib.mkAfter ''
  ${lib.getExe' pkgs.iproute2 "ip"} link set dev 'vm-ixp-as11201p' master 'ixp-peering'
'';
```

## `type = "macvtap"`

*MACVTAP* interfaces attach to a host's physical network interface,
joining the same Ethernet segment with a separate MAC address.

Before running a MicroVM interactively from a package, do the
following steps manually:

```bash
# Parent interface:
LINK=eth0
# MACVTAP interface, as specified under microvm.interfaces.*.id:
ID=microvm1
# Create the interface
sudo ip l add link $LINK name $ID type macvtap mode bridge
# Obtain the interface index number
IFINDEX=$(cat /sys/class/net/$ID/ifindex)
# Grant yourself permission
sudo chown $USER /dev/tap$IFINDEX
```

When running MicroVMs through the `host` module, the macvtap network
interfaces are created through a systemd service dependency. Per
interface with `type = "macvtap"`, a `link` attribute with the parent
interface, and `mode` attribute for the MACVTAP filtering mode must be
specified.

## `type = "bridge"`

This mode lets qemu create a tap interface and attach it to a bridge.

The `qemu-bridge-helper` binary needs to be setup with the proper
permissions. See the `host` module for that. qemu will be run
*without* `-sandbox on` in order for this contraption to work.
