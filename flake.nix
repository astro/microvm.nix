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
          qemu-example = self.lib.run "qemu" {
            inherit system;
            nixosConfig = {
              networking.hostName = "microvm";
              networking.firewall.enable = false;
              users.users.root.password = "";
            };
            # append = "boot.debugtrace";
          };

          qemu-example-service = self.lib.run "qemu" {
            inherit system;
            nixosConfig = {
              networking.hostName = "microvm-service";
              networking.firewall.enable = false;
              users.users.root.password = "";
            };
            volumes = [ {
              mountpoint = "/var";
              image = "var.img";
              size = 256;
            } ];
          };

          firecracker-example = self.lib.run "firecracker" {
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

          cloud-hypervisor-example = self.lib.run "cloud-hypervisor" {
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

          crosvm-example = self.lib.run "crosvm" {
            inherit system;
            nixosConfig = {
              networking.hostName = "microvm";
              networking.firewall.enable = false;
              networking.useDHCP = false;
              users.users.root.password = "";
            };
            volumes = [ {
              mountpoint = "/var";
              image = "var.img";
              size = 256;
            } ];
          };

        };

        checks =
            builtins.foldl' (result: hypervisor: result // {
              "microvm-${hypervisor}-test-startup-shutdown" =
                let
                  pkgs = nixpkgs.legacyPackages.${system};
                  runner = self.lib.run hypervisor {
                    inherit system;
                    nixosConfig = { pkgs, ... }: {
                      networking.hostName = "microvm-test";
                      networking.useDHCP = false;
                      systemd.services.poweroff-again = {
                        wantedBy = [ "multi-user.target" ];
                        serviceConfig.Type = "idle";
                        script =
                          let
                            exit = {
                              qemu = "reboot";
                              firecracker = "reboot";
                              cloud-hypervisor = "poweroff";
                              crosvm = "reboot";
                            }.${hypervisor};
                          in ''
                            ${pkgs.coreutils}/bin/uname > /var/OK
                            ${exit}
                          '';
                      };
                    };
                    volumes = [ {
                      mountpoint = "/var";
                      image = "var.img";
                      size = 32;
                    } ];
                  };
                in pkgs.runCommandNoCCLocal "microvm-${hypervisor}-test-startup-shutdown" {
                  buildInputs = [
                    runner
                    pkgs.libguestfs-with-appliance
                  ];
                } ''
                  ${runner.name} > $out

                  virt-cat -a var.img -m /dev/sda:/ /OK > $out
                  if [ "$(cat $out)" != "Linux" ] ; then
                    echo Output does not match
                    exit 1
                  fi
                '';
            }) {} self.lib.hypervisors;

      }) // {
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

          createVolumesScript = pkgs: nixpkgs.lib.concatMapStringsSep "\n" (
              { image, size, fsType ? self.lib.defaultFsType, ... }: ''
                PATH=$PATH:${with pkgs; lib.makeBinPath [ e2fsprogs ]}

                if [ ! -e ${image} ]; then
                  dd if=/dev/zero of=${image} bs=1M count=1 seek=${toString (size - 1)}
                  mkfs.${fsType} ${image}
                fi
              '');

          inherit (import ./lib/disk-image.nix {
            inherit self nixpkgs;
          }) mkDiskImage;

          runners = builtins.mapAttrs (hypervisor: path: (
            import path {
              inherit self nixpkgs;
            }
          ).run) {
            qemu = ./lib/hypervisors/qemu.nix;
            firecracker = ./lib/hypervisors/firecracker.nix;
            cloud-hypervisor = ./lib/hypervisors/cloud-hypervisor.nix;
            crosvm = ./lib/hypervisors/crosvm.nix;
          };
          hypervisors = builtins.attrNames self.lib.runners;
          run = hypervisor: self.lib.runners.${hypervisor};
        };
      };
}
