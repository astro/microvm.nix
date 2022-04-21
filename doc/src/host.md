# Preparing a NixOS host for declarative MicroVMs

**microvm.nix** adds the following configuration for servers to
host MicroVMs reliably:

- a `/var/lib/microvm` state directory with one subdirectory per MicroVM
- systemd services `microvm-tap-interfaces@` to setup TAP network interfaces
- systemd services `microvm-virtiofsd@` to start virtiofsd instances
- systemd services `microvm@` to start a MicroVM
- configuration options to [declaratively build MicroVMs with the host
  system](./declarative.md)
- tools to [manage MicroVMs imperatively](./microvm-command.md)

Prepare your host by including the microvm.nix `host` nixosModule:

```nix
# Your server's flake.nix
{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/unstable";
  inputs.microvm.url = "github:astro/microvm.nix";
  inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, microvm }: {
    # Example nixosConfigurations entry
    nixosConfigurations.server1 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Include the microvm host module
        microvm.nixosModules.host
        # Add more modules here
        {
          networking.hostName = "server1";
        }
      ];
    };
  };
}
```
