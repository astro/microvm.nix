# Running a MicroVM as a package

Quickly running a MicroVM interactively is great for testing. You get
to interact with its console.

There are drawbacks: no preparation for TAP network interfaces is done
and no virtiofsd is started. These can be worked around by relying on
9p shares and using qemu's `host` network interfaces.

## Immediately running a nixosConfiguration

To run a `nixosConfiguration` off your Flake directly use:
```bash
nix run .#nixosConfigurations.my-microvm.config.microvm.declaredRunner
```

## Add a runner package to your Flake

To add this runner permanently add a package like this to the outputs
of your `flake.nix`:
```nix
packages.x86_64-linux.my-microvm = self.nixosConfigurations.my-microvm.config.declaredRunner;
```

You can then run the MicroVM with a simple `nix run .#my-microvm`
