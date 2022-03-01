# MicroVM.nix

A Nix Flake to build NixOS and run it on one of several Type-2
Hypervisors on NixOS/Linux. The project is intended to provide a more
isolated alternative to `nixos-container`. You can either build and
run MicroVMs like Nix packages, or alternatively install them as
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
- MicroVMs can access stateful filesystems either on a image volume as
  a block device or as a shared directory hierarchy through virtiofsd.
- Zero, one, or more virtual tap ethernet network interfaces can be
  attached to a MicroVM.

## Hypervisors

| Hypervisor                                                              | Language | Restrictions          |
|-------------------------------------------------------------------------|----------|-----------------------|
| [qemu](https://www.qemu.org/)                                           | C        |                       |
| [cloud-hypervisor](https://www.cloudhypervisor.org/)                    | Rust     | no 9p shares          |
| [firecracker](https://firecracker-microvm.github.io/)                   | Rust     | no 9p/virtiofs shares |
| [crosvm](https://chromium.googlesource.com/chromiumos/platform/crosvm/) | Rust     | no network interfaces |
| [kvmtool](https://github.com/kvmtool/kvmtool)                           | C        | no virtiofs shares    |

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

## Configuration

### Shares

In `microvm.shares` elements the `proto` field allows either of two
values:

- `9p` (default) is built into many hypervisors, allowing you to
  quickly share a directory tree

- `virtiofs` requires a separate virtiofsd service which is only
  started as a prerequisite when you start MicroVMs through a systemd
  service that comes with the `microvm.nixosModules.host` module.

  Expect `virtiofs` to yield better performance over `9p`.

#### Sharing a host's `/nix/store`

If a share with `source = "/nix/store"` is defined, size and build
time of the stage1 squashfs for `/dev/vda` will be reduced
drastically.

```nix
microvm.shares = [ {
  tag = "ro-store";
  source = "/nix/store";
  mountPoint = "/nix/.ro-store";
} ];
```

#### Writable `/nix/store` overlay

The writable layer is mounted from the path
`microvm.writableStoreOverlay`. You may choose to add a persistent
volume or share for that mountPoint.

Recommended configuration to disable this feature, making `/nix/store`
read-only:

```nix
microvm.writableStoreOverlay = null;
```

### Network interfaces

#### `type = "user"`

User-mode networking is only provided by qemu and kvmtool, providing
outgoing connectivity to your MicroVM without any further setup.

As kvmtool seems to lack a built-in DHCP server, additional static IP
configuration is necessary inside the MicroVM.

#### `type = "tap"`

Use a virtual tuntap Ethernet interface. Its name is the value of
`id`.

Some Hypervisors may be able to automatically create these interfaces
when running as root, which we advise against. Instead, create the
interfaces before starting a microvm:

```bash
sudo ip tuntap add $IFACE_NAME mode tap user $USER
```

When running MicroVMs through the `host` module, the tap network
interfaces are created through a systemd service dependency.

#### `type = "bridge"`

This mode lets qemu create a tap interface and attach it to a bridge.

The `qemu-bridge-helper` binary needs to be setup with the proper
permissions. See the `host` module for that. qemu will be run
*without* `-sandbox on` in order for this contraption to work.

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

At last, check the validity of the symlinks in
`/nix/var/nix/gcroots/microvm`.

## Commercial support

The author can be hired to implement the features that you wish, or to
integrate this tool into your toolchain. If in doubt, just press the
💗sponsor button.

## Ideas

- [x] Boot with root off virtiofs, avoiding overhead of creating squashfs image
- [x] Provide a writable `/nix/store`
- [ ] Distribute/fail-over MicroVMs at run-time within a cluster of hosts
