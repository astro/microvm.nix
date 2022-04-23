# Frequently Asked Questions

A few caveats. Contributions to eliminate those are welcome.


## Why build a kernel with a custom config?

Hypervisors are not required to be able to load an
initrd/initramfs. Therefore we start init from a virtio disk which
requires virtio drivers to be built in statically.

Because we are building our own kernel anyway, we've got the
opportunity of adding more custom config that is optimized for common
MicroVM use-cases.
