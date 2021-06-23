{
  description = "Contain NixOS in a MicroVM";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      
        packages = {
          qemu-example = self.lib.runQemu {
            inherit system;
            nixos = nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [ (
                { modulesPath, ... }:

                {
                  imports = [
                    (modulesPath + "/profiles/minimal.nix")
                  ];

                  boot.isContainer = true;
                  networking.hostName = "microvm";
                  networking.firewall.enable = false;
                  users.users.root.password = "";
                }
              ) ];
            };
            # append = "boot.debugtrace";
          };

          qemu-example-service = self.lib.runQemu {
            inherit system;
            nixos = nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [ (
                { modulesPath, ... }:

                {
                  imports = [
                    (modulesPath + "/profiles/minimal.nix")
                  ];

                  boot.isContainer = true;
                  networking.hostName = "microvm-service";
                  networking.firewall.enable = false;
                  users.users.root.password = "";

                  fileSystems."/var" = {
                    device = "var";
                    fsType = "9p";
                    options = [ "trans=virtio" "version=9p2000.L" "cache=loose" "msize=65536" ];
                    neededForBoot = true;
                  };
                }
              ) ];
            };
            preStart = ''
              mkdir -p ./var
            '';
            shared = [ {
              id = "var";
              writable = true;
              path = "./var";
            } ];
          };
        };

      }
    ) // {
      lib = {
        inherit (import ./qemu/lib.nix {
          inherit self nixpkgs;
        }) runQemu;
      };
    };
}
