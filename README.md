# MicroVM.nix

A Nix Flake to build NixOS and run it on one of several Type-2 Hypervisors.

## Examples

```shell
nix-shell -p nixFlakes
nix run .#qemu-example
nix run .#firecracker-example
nix run .#cloud-hypervisor-example
nix run .#crosvm-example
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
