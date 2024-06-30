# CPU emulation

It's possible to emulate a CPU if desired. This feature is only
supported by the qemu VMM.

**Note:** this feature has a significant performance impact.

## Defining an emulated NixOS system

You can call to `nixpkgs.lib.nixosSystem`, with the following key
settings:

- Set the `system` attribute to the host system.

- A module that sets `nixpkgs.crossSystem.config` to the guest
  system. This lets `microvm.nix` know that it's a cross-system
  environment.

- Set `microvm.hypervisor` to `qemu`, given this is the only
  VMM that supports this feature.

- Set `microvm.cpu` to the desired emulated CPU. You can find a [list
  of the available systems
  here](https://www.qemu.org/docs/master/system/targets.html).

```nix
# Example flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm }: {
    emulated-dev = nixpkgs.lib.nixosSystem {
      # host system
      system = "x86_64-linux";
      modules = let
        guestSystem = "aarch64-unknown-linux-gnu";
        # you can use packages in the guest machine with cross system configuration
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          crossSystem.config = guestSystem;
        };
      in [
        {nixpkgs.crossSystem.config = guestSystem;}
        microvm.nixosModules.microvm
        {
          microvm = {
            # you can choose what CPU will be emulated by qemu
            cpu = "cortex-a53";
            hypervisor = "qemu";
          };
          environment.systemPackages = with pkgs; [ cowsay htop ];
          services.getty.autologinUser = "root";
          system.stateVersion = "23.11";
        }
      ];
    };
  };
}
```

You can run the example with `nix run
.#emulated-dev.config.microvm.declaredRunner`.

As shown in this example, you can use system packages on the guest
system by using nixpkgs with a proper `crossSystem` configuration.
