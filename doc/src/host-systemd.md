# systemd services on a MicroVM host

The `host` nixosModule provides a few systemd services for additional
bringup which is not available when running a MicroVM interactively
from a package.

## `install-microvm-${name}.service`

Creates and prepares a subdirectory under `/var/lib/microvms`
according to the `microvm.vms` option if it does not already exist.

## `microvm-tap-interfaces@.service`

Creates TAP virtual network interfaces for the user that will run MicroVMs.

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
