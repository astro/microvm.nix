# Conventions between MicroVM packages and the host

This section describes the interface that is used to run MicroVM
packages with the flake's `host` module. While the **microvm.nix**
flake was designed for single-server usage, you can build different
MicroVM deployments using the information on this page.

| `nixosModule.microvm` option | MicroVM package file                   | `nixosModules.host` systemd service | Description                                                                                   |
|------------------------------|----------------------------------------|-------------------------------------|-----------------------------------------------------------------------------------------------|
| `microvm.hypervisor`         | `bin/microvm-run`                      | `microvm@.service`                  | Start script for the main MicroVM process                                                     |
| `microvm.hypervisor`         | `bin/microvm-shutdown`                 | `microvm@.service`                  | Script for graceful shutdown of the MicroVM (e.g. triggering the power button)                |
| `microvm.interfaces.*.id`    | `share/microvm/tap-interfaces`         | `microvm-tap-interfaces@.service`   | Names of the tap network interfaces to setup for the proper user                              |
| `microvm.devices.*.path`     | `share/microvm/pci-devices`            | `microvm-pci-devices@.service`      | PCI devices that must be bound to the **vfio-pci** driver on the host                         |
| `microvm.shares.*.source`    | `share/microvm/virtiofs/${tag}/source` | `microvm-virtiofsd@.service`        | Source directory of a **virtiofs** instance by tag                                            |
| `microvm.shares.*.socket`    | `share/microvm/virtiofs/${tag}/socket` | `microvm-virtiofsd@.service`        | **virtiofsd** socket path by tag                                                              |
|                              | `share/microvm/system`                 |                                     | `config.system.build.toplevel` symlink, used for comparing versions when running `microvm -l` |
