{
  description = "NixOS in MicroVMs";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05";
  inputs.microvm.url = "github:astro/microvm.nix";
  inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
    in {
      defaultPackage.${system} = self.packages.${system}.my-microvm;

      packages.${system}.my-microvm =
        let
          inherit (self.nixosConfigurations.my-microvm) config;
          # quickly build with another hypervisor if this MicroVM is built as a package
          hypervisor = "qemu";
        in config.microvm.runner.${hypervisor};

      nixosConfigurations.my-microvm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          {
            networking.hostName = "my-microvm";
            users.users.root.password = "";
            microvm = {
              volumes = [ {
                mountPoint = "/var";
                image = "var.img";
                size = 256;
              } ];
              socket = "control.socket";
              # relevant for delarative MicroVM management
              hypervisor = "qemu";
            };
          }
        ];
      };
    };
}
