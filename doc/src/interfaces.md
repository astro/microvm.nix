# Network interfaces

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
interfaces before starting a microvm:

```bash
sudo ip tuntap add $IFACE_NAME mode tap user $USER
```

When running MicroVMs through the `host` module, the tap network
interfaces are created through a systemd service dependency.

## `type = "bridge"`

This mode lets qemu create a tap interface and attach it to a bridge.

The `qemu-bridge-helper` binary needs to be setup with the proper
permissions. See the `host` module for that. qemu will be run
*without* `-sandbox on` in order for this contraption to work.

