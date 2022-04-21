# Declaring NixOS MicroVMs

microvm.nix creates virtual machine disk images and runner script
packages for the entries of the `nixosConfigurations` section of a
`flake.nix` file.

## The `microvm` module

To add MicroVM functionality, a NixOS system configuration is
augmented by importing this flake's `nixosModule.microvm`:

```nix
# Example flake.nix
{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/unstable";
  inputs.microvm.url = "github:astro/microvm.nix";
  inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, microvm }: {
    # Example nixosConfigurations entry
    nixosConfigurations.my-microvm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Include the microvm module
        microvm.nixosModules.microvm
        # Add more modules here
        {
          networking.hostName = "my-microvm";
          microvm.hypervisor = "cloud-hypervisor";
        }
      ];
    };
  };
}
```
