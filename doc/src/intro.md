# Intro

**microvm.nix** is a Flake to run lightweight NixOS virtual machines
on NixOS. Starting with the reasons why for the remainder of this
chapter, this handbook guides you through the provisioning of MicroVMs
on your NixOS machine.

## Compartmentalization

NixOS makes running services a breeze. Being able to quickly rollback
configuration is a life-saver. Not so much however on systems that are
shared by multiple services where maintainance of one affects others.

Increase stability by partitioning services into virtual NixOS systems
that can be updated individually.

## The Case Against Containers

Linux containers are not a single technology but a plethora of kernel
features that serve to isolate various system resources so that the
running system appears as one. It is still one shared Linux kernel
with a huge attack surface.

Virtual machines on the other hand run their own OS kernel, reducing
the attack surface to the hypervisor and its device drivers. The
resource usage however incurs some overhead when compared with
containers, with memory alloction being especially inflexible.

**microvm.nix** ships an additional security feature: the root
filesystem is a read-only squashfs that includes only the binaries of
your configuration. That of course holds only true unless you mount the
host's /nix/store as a share for faster build times, or mount the
store with a writable overlay.

## Just Virtual Machines?

Full virtualization has been available for a long time with QEMU and
VirtualBox. The *MicroVM* movement wants to express that
virtualization overhead has been reduced a lot by replacing emulated
devices with *virtio* interfaces that have been optimized for an
emulated environment.

This Flake offers you to run your MicroVMs not only on QEMU but with
other Hypervisors that have been explicitly authored for
*virtio*. Some of them are written in Rust, a programming language
that is renowned for being safer than C.
