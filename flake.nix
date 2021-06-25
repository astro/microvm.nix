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
            };
            preStart = ''
              mkdir -p ./var
            '';
            shared = [ {
              id = "var";
              writable = true;
              path = "./var";
              mountpoint = "/var";
            } ];
          };

          firecracker-example = self.lib.runFirecracker {
            inherit system;
            nixosConfig = {
              networking.hostName = "microvm";
              networking.firewall.enable = false;
              users.users.root.password = "";
            };
            interfaces = [ {
              id = "qemu";
              mac = "00:00:23:42:24:32";
            } ];
            volumes = [ {
              mountpoint = "/var";
              image = "var.img";
              size = 256;
            } ];
          };

          cloud-hypervisor-example = self.lib.runCloudHypervisor {
            inherit system;
            nixosConfig = {
              networking.hostName = "microvm";
              networking.firewall.enable = false;
              users.users.root.password = "";
            };
            interfaces = [ {
              id = "qemu";
              mac = "00:00:23:42:24:32";
            } ];
            volumes = [ {
              mountpoint = "/var";
              image = "var.img";
              size = 256;
            } ];
          };

          crosvm-example = self.lib.runCrosvm {
            inherit system;
            nixosConfig = {
              networking.hostName = "microvm";
              networking.firewall.enable = false;
              networking.useDHCP = false;
              users.users.root.password = "";
            };
          };

        };

      }
      ) // {
        lib = {
          defaultFsType = "ext4";

          withDriveLetters = offset: list:
            map ({ fst, snd }:
              fst // {
                letter = snd;
              }
            ) (nixpkgs.lib.zipLists list (
              nixpkgs.lib.drop offset nixpkgs.lib.strings.lowerChars
            ));

          createVolumesScript = nixpkgs.lib.concatMapStringsSep "\n" ({ image, size, fsType ? self.lib.defaultFsType, ... }: ''
            if [ ! -e ${image} ]; then
              dd if=/dev/zero of=${image} bs=1M count=1 seek=${toString (size - 1)}
              mkfs.${fsType} ${image}
            fi
          '');

          inherit (import ./lib/disk-image.nix {
            inherit self nixpkgs;
          }) mkDiskImage;

          inherit (import ./qemu/lib.nix {
            inherit self nixpkgs;
          }) runQemu;
          inherit (import ./firecracker/lib.nix {
            inherit self nixpkgs;
          }) runFirecracker;
          inherit (import ./cloud-hypervisor/lib.nix {
            inherit self nixpkgs;
          }) runCloudHypervisor;
          inherit (import ./crosvm/lib.nix {
            inherit self nixpkgs;
          }) runCrosvm;
        };
      };
}
