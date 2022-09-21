# MicroVM.nix

<p align="center">
  <strong>Handbook:</strong>
  <a href="https://astro.github.io/microvm.nix/">HTML</a>
  <a href="doc/src/TOC.md">Markdown</a>
  •
  <strong><a href="https://github.com/sponsors/astro">Support the project</a></strong>
</p>
<p align="center">
  <img src="doc/src/demo.gif" alt="Demo GIF">
</p>

A Nix Flake to build NixOS and run it on one of several Type-2
Hypervisors on NixOS/Linux. The project is intended to provide a more
isolated alternative to `nixos-container`. You can either build and
run MicroVMs like Nix packages, or alternatively install them as
systemd services declaratively in your host's Nix Flake or
imperatively with the provided `microvm` command.

**Warning:** This is a *Nix Flakes*-only project. Use with `nix-shell -p nixFlakes`

## At a glance

- MicroVMs are Virtual Machines but use special device interfaces
  (virtio) for high performance
- This project runs them on NixOS hosts
- You can choose one of five hypervisors for each MicroVM
- MicroVMs have a fixed RAM allocation (default: 512 MB)
- MicroVMs have a read-only root disk with either a prepopulated
  `/nix/store` or by mounting the host's along with an optional
  writable overlay
- You define your MicroVMs in a Nix Flake's `nixosConfigurations`
  section, reusing the `nixosModules` that are exported by this Flake
- MicroVMs can access stateful filesystems either on a image volume as
  a block device or as a shared directory hierarchy through 9p or
  virtiofs.
- Zero, one, or more virtual tap ethernet network interfaces can be
  attached to a MicroVM.

## Hypervisors

| Hypervisor                                                              | Language | Restrictions                             |
|-------------------------------------------------------------------------|----------|------------------------------------------|
| [qemu](https://www.qemu.org/)                                           | C        |                                          |
| [cloud-hypervisor](https://www.cloudhypervisor.org/)                    | Rust     | no 9p shares                             |
| [firecracker](https://firecracker-microvm.github.io/)                   | Rust     | no 9p/virtiofs shares                    |
| [crosvm](https://chromium.googlesource.com/chromiumos/platform/crosvm/) | Rust     | no control socket |
| [kvmtool](https://github.com/kvmtool/kvmtool)                           | C        | no virtiofs shares, no control socket    |

While ubiquitous qemu seems to work in most situations, other
hypervisors tend to break with Linux kernel updates. Especially crosvm
and kvmtool need a lot of luck to get going.

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

## Commercial support

The author can be hired to implement the features that you wish, or to
integrate this tool into your toolchain. If in doubt, just press the
💗sponsor button.
