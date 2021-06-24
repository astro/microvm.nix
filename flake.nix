{
  description = "Contain NixOS in a MicroVM";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
      flake-utils.lib.eachSystem systems (system: {
        
        packages = (
          import ./pkgs/kernel.nix {
            inherit self nixpkgs system;
          }
        ) // {
          qemu-example = self.lib.runQemu {
            inherit system;
            nixosConfig = {
              networking.hostName = "microvm";
              networking.firewall.enable = false;
              users.users.root.password = "";
            };
            # append = "boot.debugtrace";
          };

          qemu-example-service = self.lib.runQemu {
            inherit system;
            nixosConfig = {
              networking.hostName = "microvm-service";
              networking.firewall.enable = false;
              users.users.root.password = "";

              fileSystems."/var" = {
                device = "var";
                fsType = "9p";
                options = [ "trans=virtio" "version=9p2000.L" "cache=loose" "msize=65536" ];
                neededForBoot = true;
              };
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

          firecracker-example = self.lib.runFirecracker {
            inherit system;
            nixosConfig = {
              networking.hostName = "microvm";
              networking.firewall.enable = false;
              users.users.root.password = "";
            };
            append = "boot.debugtrace";
            interfaces = [ {
              id = "qemu";
              mac = "00:00:23:42:24:32";
            } ];
          };

        };

      }
      ) // {
        lib = {
          inherit (import ./qemu/lib.nix {
            inherit self nixpkgs;
          }) runQemu;
          inherit (import ./firecracker/lib.nix {
            inherit self nixpkgs;
          }) runFirecracker;
        };
      };
}
