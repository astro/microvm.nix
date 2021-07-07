# MicroVM.nix

A Nix Flake to build NixOS and run it on one of several Type-2 Hypervisors.

**Warning:** This is a *Nix Flakes*-only project. Use with `nix-shell -p nixFlakes`

## Installation

```shell
nix registry add microvm git+https://github.com/astro/microvm.nix.git
```

## Examples

Instead of checking out this repository, you can can replace `.` with
`microvm` if you added the Flake to your local Registry as shown above.

```shell
nix run .#qemu-example
nix run .#firecracker-example
nix run .#cloud-hypervisor-example
nix run .#crosvm-example
```

Run a proper NixOS virtual machine with four example MicroVMs:

```shell
nix run .#vm
```

# TODO

- [x] qemu
- [x] Firecracker
- [x] Cloud-Hypervisor
- [x] crosvm

- [x] Volumes
- [x] Tests
- [ ] Kernel config unification
- [ ] Control sockets for clean shutdown
