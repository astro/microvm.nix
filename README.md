# MicroVM.nix

A Nix Flake to build NixOS and run it on one of several Type-2
Hypervisors on NixOS/Linux. The project's intention is to provide a
more isolated alternative to `nixos-container`. You can either build
and run them like Nix packages, or alternatively install them as
systemd services declaratively in your host's Nix Flake or
impereratively with the provided `microvm` command.

**Warning:** This is a *Nix Flakes*-only project. Use with `nix-shell -p nixFlakes`

## At a glance

- MicroVMs are Virtual Machines but use special device interfaces
  (virtio) for high performance
- This project runs them on NixOS hosts
- You can choose one of five hypervisors for each MicroVM
- MicroVMs have a fixed RAM allocation (default: 512 MB)
- MicroVMs have a read-only root disk with a prepopulated `/nix/store`
- You define your MicroVMs in a Nix Flake's `nixosConfigurations`
  section, reusing the `nixosModules` that are exported by this Flake

## Hypervisors

| Hypervisor                                                              | Language | Restrictions                              |
|-------------------------------------------------------------------------|----------|-------------------------------------------|
| [qemu](https://www.qemu.org/)                                           | C        |                                           |
| [cloud-hypervisor](https://www.cloudhypervisor.org/)                    | Rust     |                                           |
| [firecracker](https://firecracker-microvm.github.io/)                   | Rust     | no virtiofs shares                        |
| [crosvm](https://chromium.googlesource.com/chromiumos/platform/crosvm/) | Rust     | no virtiofs shares, no network interfaces |
| [kvmtool](https://github.com/kvmtool/kvmtool)                           | C        | no virtiofs shares                        |

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

Use this on a (physical) machine that is supposed to host MicroVMs.

#### Declarative MicroVMs configuration

Declare MicroVMs in your host's nixosSystem.

This method is meant to be used to ensure the presence of a
MicroVM. It will not update preexisting MicroVMs in
`/var/lib/microvm`. Use the imperative `microvm` command to do that.

```nix
microvm.vms."my-microvm" = {
  # Source flake for `nixos-rebuild` of the host
  flake = self;
  # Source flakeref for `microvm -u my-microvm`
  updateFlake = "git+https://...";
};
```

#### Imperative MicroVM management

```bash
# Create my-microvm
microvm -f git+https://... -c my-microvm
# Update my-microvm
microvm -u my-microvm
# List MicroVMs
microvm -l
```

### `microvm.nixosModules.microvm`

Import this module in your MicroVM's nixosSystem. Refer to
[nixos-modules/microvm/options.nix](nixos-modules/microvm/options.nix)
for MicroVM-related config.

## Migrating from 0.1.0 to 0.2.0

Your Flake does no longer need to provide the MicroVMs as packages. An
entry for each MicroVM in `nixosConfiguration` is enough.

To get a MicroVM's hypervisor runner as a package, use:

```bash
nix build myflake#nixosConfigurations.my-microvm.config.microvm.runner.qemu
```

MicroVM parameters have moved inside the NixOS configuration, gaining
parameter validation through the module system. Refer to
`nixos-modules/microvm/options.nix` for their definitions.

### Cleaning up /var/lib/microvms/*

Delete the following remnants from 0.1.0:

- `microvm-run`
- `microvm-shutdown`
- `tap-interfaces`
- `virtiofs`

All these copied files are now behind the `current` symlink to a
Hypervisor runner package.


## Ideas

- [ ] Boot with root off virtiofs, avoiding overhead of creating squashfs image
- [ ] Provide a writable `/nix/store`
- [ ] Distribute/fail-over MicroVMs at run-time within a cluster of hosts
