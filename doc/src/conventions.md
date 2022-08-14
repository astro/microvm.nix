# Conventions between MicroVM packages and the host

This section describes the interface that is used to run MicroVM
packages with the `host` module. While the **microvm.nix** flake was
designed for single-server usage, you can build different MicroVM
deployments using the information on this page.

| MicroVM package file                   | `host` systemd service            | Description                                                                                                                        |
|----------------------------------------|-----------------------------------|------------------------------------------------------------------------------------------------------------------------------------|
| `bin/microvm-run`                      | `microvm@.service`                | Start script for the main MicroVM process                                                                                          |
| `bin/microvm-shutdown`                 | `microvm@.service`                | Script for graceful shutdown of the MicroVM (ie. triggering the power button)                                                      |
| `share/microvm/system`                 |                                   | The result of `config.system.build.toplevel`, used for comparing versions with `nix store diff-closures` when running `microvm -l` |
| `share/microvm/tap-interfaces`         | `microvm-tap-interfaces@.service` | Contains the names of the tap network interfaces to setup for the proper user.                                                     |
| `share/microvm/pci-devices`            | `microvm-pci-devices@.service`    | IDs of PCI devices that must be bound to the **vfio-pci** driver on the host.                                                      |
| `share/microvm/virtiofs/${tag}/source` | `microvm-virtiofsd@.service`      | Source directory of a **virtiofs** instance by tag                                                                                 |
| `share/microvm/virtiofs/${tag}/socket` | `microvm-virtiofsd@.service`      | **virtiofsd*** socket path by tag                                                                                                  |
