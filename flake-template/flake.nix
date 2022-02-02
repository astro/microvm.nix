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

      nixosConfigurations.my-microvm = (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          {
            networking.hostName = "my-microvm";
            users.users.root.password = "";
            microvm = {
              volumes = [ {
                mountpoint = "/var";
                image = "var.img";
                size = 256;
              } ];
              socket = "control.socket";
            };
          }
        ]
      }).config.microvm.runner.qemu;
    };
}
