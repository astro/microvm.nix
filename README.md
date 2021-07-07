# MicroVM.nix

A Nix Flake to build NixOS and run it on one of several Type-2 Hypervisors.

**Warning:** This is a *Nix Flakes*-only project. Use with `nix-shell -p nixFlakes`

## Installation

```shell
nix registry add microvm git+https://github.com/astro/microvm.nix.git
```

## Start your own NixOS MicroVM definitions

```shell
nix flake init -t microvm
```

## Examples

```shell
nix run microvm#qemu-example
nix run microvm#firecracker-example
nix run microvm#cloud-hypervisor-example
nix run microvm#crosvm-example
```

Run a proper NixOS virtual machine with four example MicroVMs:

```shell
nix run microvm#vm
```

## NixOS modules

### `microvm.nixosModules.host`

* Declarative configuration of MicroVMs with `microvm.vms`
* The `microvm` command to imperatively manage the installation

Use this on a (physical) machine that is supposed to host MicroVMs.

### `microvm.nixosModules.host`

This module is automatically included in MicroVMs.


# TODO

- [x] qemu
- [x] Firecracker
- [x] Cloud-Hypervisor
- [x] crosvm

- [x] Volumes
- [x] Tests
- [ ] Kernel config unification
- [ ] Control sockets for clean shutdown
