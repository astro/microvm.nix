# MicroVM.nix

A Nix Flake to build NixOS and run it on one of several Type-2 Hypervisors.

**Warning:** This is a *Nix Flakes*-only project. Use with `nix-shell -p nixFlakes`

## Installation

```shell
nix registry add microvm github:astro/microvm.nix
```

(If you do not want to inflict this change on your system, just
replace `microvm` with `github:astro/microvm.nix` in the following
examples.)

## Start your own NixOS MicroVM definitions

```shell
nix flake init -t microvm
```

## Examples

### Run MicroVMs on your local machine

```shell
nix run microvm#qemu-example
nix run microvm#firecracker-example
nix run microvm#cloud-hypervisor-example
nix run microvm#crosvm-example
nix run microvm#kvmtool-example
```

### Run a MicroVM example with nested MicroVMs on 5 different Hypervisors

```shell
nix run microvm#vm
```

Check `networkctl status virbr0` for the DHCP leases of the
MicroVMs. They listen for ssh with an empty root password.


## NixOS modules

### `microvm.nixosModules.host`

* Declarative configuration of MicroVMs with `microvm.vms`
* The `microvm` command to imperatively manage the installation

Use this on a (physical) machine that is supposed to host MicroVMs.

### `microvm.nixosModules.microvm`


## Ideas

- [ ] Boot with root off virtiofs, avoiding overhead of creating squashfs image
- [ ] Provide a writable `/nix/store`
- [ ] Distribute/fail-over MicroVMs at run-time within a cluster of hosts
