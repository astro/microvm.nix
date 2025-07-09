# Configuration options

By including the `microvm` module a set of NixOS options is made
available for customization. These are the most important ones:

| Option                         | Purpose                                                                                             |
|--------------------------------|-----------------------------------------------------------------------------------------------------|
| `microvm.hypervisor`           | VMM to use by default in `microvm.declaredRunner`                                                   |
| `microvm.vcpu`                 | Number of Virtual CPU cores                                                                         |
| `microvm.mem`                  | RAM allocation in MB                                                                                |
| `microvm.interfaces`           | Network interfaces                                                                                  |
| `microvm.volumes`              | Block device images                                                                                 |
| `microvm.shares`               | Shared filesystem directories                                                                       |
| `microvm.devices`              | PCI/USB devices for host-to-vm passthrough                                                          |
| `microvm.socket`               | Control socket for the VMM so that a MicroVM can be shutdown cleanly                                |
| `microvm.user`                 | (qemu only) User account which Qemu will switch to when started as root                             |
| `microvm.forwardPorts`         | (qemu user-networking only) TCP/UDP port forwarding                                                 |
| `microvm.kernelParams`         | Like `boot.kernelParams` but will not end up in `system.build.toplevel`, saving you rebuilds        |
| `microvm.storeOnDisk`          | Enables the store on the boot squashfs even in the presence of a share with the host's `/nix/store` |
| `microvm.writableStoreOverlay` | Optional string of the path where all writes to `/nix/store` should go to.                          |

See [the options declarations](
https://github.com/astro/microvm.nix/blob/main/nixos-modules/microvm/options.nix)
for a full reference.
