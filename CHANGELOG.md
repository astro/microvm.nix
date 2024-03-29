# Major Changes in microvm.nix

## 0.5.0 (To be released)

* **tap interfaces** are now **multi-queue** when running with more
  than one VCPU. Update your host!
* The `host` module enables **Kernel Samepage Merging** by default.
* **qemu** can run non-native systems by using its **Tiny Code
  Generator** instead of KVM.
* **SSH deployment scripts** are added as
  `config.microvm.deploy.rebuild`
* **qemu** gets rid of the *q35* machine model entirely as the
  *microvm* model supports PCI, USB, and ACPI by now.
* The NixOS **hardened** profile can be used by falling back to
  *squashfs*.
* Runners execute the hypervisor with a process name of
  `microvm@$NAME`
* We no longer let `environment.noXlibs` default to `true`
* **Breaking:** the `microvm` user is no longer in the `disk` group
  for security reasons. Add `users.users.microvm.extraGroups = [
  "disk" ]` to your config to restore the old behavior.

## 0.4.1 (2023-11-03)

* **cloud-hypervisor** replaces **rust-hypervisor-firmware** with
  direct kernel+initramfs loading.
* The microvm module now optimizes the NixOS configuration for size.
* **crosvm** now supports **macvtap** interfaces.
* The option `microvm.qemu.bios` has been dropped again for simplicity
  reasons.

  **qemu** boots fast with the shipped SeaBIOS if after both SATA and
  the network interface option ROM (iPXE) have been disabled.
* `microvm.kernelParams` always copy `boot.kernelParams`
* **firecracker** is no longer launched through **firectl**.
* Networking example documentation has been split into multiple
  scenarios.
* **Vsock** support has been added for Hypervisors that connect them
  to the Linux host's *AF_VSOCK*: qemu, crosvm, and kvmtool.
* Our packages and overlay include the unstable version of
  **waypipe**, featuring **Vsock** support.
* Add support for the old command-line parameter syntax that returned
  with **cloud-hypervisor** 36.0.

## 0.4.0 (2023-07-09)

* Stop building a custom kernel by booting the NixOS kernel with an
  initrd.
* New Hypervisor: **stratovirt** by Huawei
* Support *fully declarative* MicroVMs that are part of the host's
  NixOS configuration. **No Flakes required!**
* We use **squashfs-tools-ng** now.
* The `microvm-console` script has been removed because pty console
  setup was too cumbersome to maintain across all hypervisors.
* `microvm.storeDiskType` defaults to `"erofs"` now for higher runtime
  performance.

## 0.3.3 (2023-05-24)

* Support for **macvtap** network interfaces has been added.
* `boot.initrd.systemd.enable` is now supported.
* Experimental **graphics** support for qemu, and cloud-hypervisor
* **qemu**: use qboot BIOS

## 0.3.2 (2022-12-25)
