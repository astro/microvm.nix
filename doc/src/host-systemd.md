# systemd services on a MicroVM host

The `host` nixosModule provides a few systemd services for additional
bringup which is not available when running a MicroVM interactively
from a package.

## `install-microvm-${name}.service`

Creates and prepares a subdirectory under `/var/lib/microvms` for
[declarative MicroVMs](./declarative.md) according to the
`microvm.vms` option.

If the MicroVM subdirectory under `/var/lib/microvms` already exists,
**and** the MicroVM is configured to be built from a flake's
`nixosConfigurations`, this systemd unit will be skipped. The reason
for this behavior is that it is easier to update with the [`microvm`
command](./microvm-command.md) instead of restarting all virtual
machines on a host when doing `nixos-rebuild switch`.

## `microvm-tap-interfaces@.service`

Creates TAP virtual network interfaces for the user that will run MicroVMs.

## `microvm-macvtap-interfaces@.service`

Creates MACVTAP virtual network interfaces for the user that will run MicroVMs.

## `microvm-pci-devices@.service`

Prepares PCI devices for passthrough
([VFIO](https://www.kernel.org/doc/html/latest/driver-api/vfio.html)).

## `microvm-virtiofsd@.service`

Starts a fleet of virtiofsd servers, one for each `virtiofs`
mountpoint in `microvm.shares`.

## `microvm@.service`

Runs the actual MicroVM through
`/var/lib/microvms/%i/current/bin/microvm-run` where `%i` is the
MicroVM name.

## `microvms.target`

Depends on the `microvm@.service` instance for all configured
`microvm.autostart`.
