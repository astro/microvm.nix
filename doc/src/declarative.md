# Declarative MicroVMs

Provided your NixOS host [includes the host nixosModule](./host.md),
options are declared to build a MicroVM with the host so that it gets
deployed and start on boot.

Why *deployed*? The per-MicroVM subdirectory under `/var/lib/microvm`
gets only created if it did not exist before. This behavior is
intended to ensure existence of MicroVMs that are critical to
operation. To update later use the [imperative microvm
command](./microvm-command.md).

```nix
microvm.vms = {
  my-microvm = {
    # Host build-time reference to where the MicroVM NixOS is defined
    # under nixosConfigurations
    flake = self;
    # Specify from where to let `microvm -u` update later on
    updateFlake = "git+file:///etc/nixos";
  };
};
```

Note that building MicroVMs with the host increases build time and
closure size of the host's system.
