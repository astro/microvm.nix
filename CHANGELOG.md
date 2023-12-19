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

## 0.4.1 (2023-11-03)

* **cloud-hypervisor** replaces **rust-hypervisor-firmware** with
  direct kernel+initramfs loading.
* The microvm module now optimizes the NixOS configuration for size.
* **crosvm** now supports **macvtap** interfaces.
* Drop `microvm.qemu.bios` for simplicity.
* `microvm.kernelParams` always reuse `boot.kernelParams`
* **firecracker** is no longer launched through **firectl**.
* Networking example documentation has been split into multiple
  scenarios.
* **Vsocks** support has been added for Hypervisors that connect it to
  the Linux host's *AF_VSOCK*: qemu, and crosvm.

## 0.4.0 (2023-07-09)

* Stop building a custom kernel by booting the NixOS kernel with an
  initrd.
* New Hypervisor: **stratovirt** by Huawei
* Support *fully declarative* MicroVMs that are part of the host's
  NixOS configuration. **No Flakes required!**
* We use **squashfs-tools-ng** now.

## 0.3.3 (2023-05-24)

* Support for **macvtap** network interfaces has been added.
* `boot.initrd.systemd.enable` is now supported.
* Experimental **graphics** support
* **qemu**: use qboot BIOS

## 0.3.2 (2022-12-25)
