# Frequently Asked Questions

A few caveats. Contributions to eliminate those are welcome.


## Why build a kernel with a custom config?

Hypervisors are not required to be able to load an
initrd/initramfs. Therefore we start init from a virtio disk which
requires virtio drivers to be built into the kernel statically.

Because we are building our own kernel anyway, we've got the
opportunity of adding more custom config that is optimized for common
MicroVM use-cases.


## How to centralize logging with journald?

That is possible without even requiring a network transport by just
making the journals available to the host as a share. Because journald
identifies hosts by their `/etc/machine-id`, we propose to use static
content for that file. Add a NixOS module like the following to your
MicroVM configuration:

```nix
environment.etc."machine-id" = {
  mode = "0644";
  text =
    # change this to suit your flake's interface
    self.lib.addresses.machineId.${config.networking.hostName} + "\n";
};

microvm.shares = [ {
  # On the host
  source = "/var/lib/microvms/${config.networking.hostName}/journal";
  # In the MicroVM
  mountPoint = "/var/log/journal";
  tag = "journal";
  proto = "virtiofs";
  socket = "journal.sock";
} ];
```

Last, make the MicroVM journals available to your host. The
`machine-id` must be available.

```nix
systemd.tmpfiles.rules = map (vmHost:
  let
    machineId = self.lib.addresses.machineId.${vmHost};
  in
    # creates a symlink of each MicroVM's journal under the host's /var/log/journal
    "L+ /var/log/journal/${machineId} - - - /var/lib/microvms/${vmHost}/journal/${machineId}"
) (builtins.attrNames self.lib.addresses.machineId);
```

`-m`
