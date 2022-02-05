{
  description = "Contain NixOS in a MicroVM";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-21.11";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
      flake-utils.lib.eachSystem systems (system: {

        apps = {
          vm = {
            type = "app";
            program =
              let
                inherit (import ./examples/microvms-host.nix {
                  inherit self nixpkgs system;
                }) config;
                inherit (config.microvm) hypervisor;
              in
                "${config.microvm.runner.${hypervisor}}/bin/microvm-run";
          };
        };

        packages =
          {
            microvm-kernel = nixpkgs.legacyPackages.${system}.kernelPackages_latest.callPackage ./pkgs/microvm-kernel.nix {};
            microvm = import ./pkgs/microvm-command.nix {
              pkgs = nixpkgs.legacyPackages.${system};
            };
          } //
          # wrap self.nixosConfigurations in executable packages
          builtins.foldl' (result: systemName:
            let
              nixos = self.nixosConfigurations.${systemName};
              name = builtins.replaceStrings [ "${system}-" ] [ "" ] systemName;
              inherit (nixos.config.microvm) hypervisor;
            in
              if nixos.pkgs.system == system
              then result // {
                "${name}" = nixos.config.microvm.runner.${hypervisor};
              }
              else result
          ) {} (builtins.attrNames self.nixosConfigurations);

        checks =
          builtins.foldl' (result: hypervisor: result // {
            # Run a MicroVM that immediately shuts down again
            "microvm-${hypervisor}-test-startup-shutdown" =
              let
                pkgs = nixpkgs.legacyPackages.${system};
                microvm = (nixpkgs.lib.nixosSystem {
                  inherit system;
                  modules = [
                    self.nixosModules.microvm
                    ({ pkgs, ... }: {
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
                              kvmtool = "reboot";
                            }.${hypervisor};
                          in ''
                          ${pkgs.coreutils}/bin/uname > /var/OK
                          ${exit}
                        '';
                      };
                      microvm.volumes = [ {
                        mountPoint = "/var";
                        image = "var.img";
                        size = 32;
                      } ];
                    })
                  ];
                }).config.microvm.runner.${hypervisor};
              in pkgs.runCommandNoCCLocal "microvm-${hypervisor}-test-startup-shutdown" {
                buildInputs = [
                  microvm
                  pkgs.libguestfs-with-appliance
                ];
              } ''
                microvm-run

                virt-cat -a var.img -m /dev/sda:/ /OK > $out
                if [ "$(cat $out)" != "Linux" ] ; then
                  echo Output does not match
                  exit 1
                fi
              '';
            # Run a VM with a MicroVM
            "vm-host-microvm-${hypervisor}" = import (nixpkgs + "/nixos/tests/make-test-python.nix") ({ ... }: {
              name = "vm-host-microvm-${hypervisor}";
              nodes.vm = {
                imports = [ self.nixosModules.host ];
                microvm.vms."${hypervisor}-example".flake = self;
              };
              testScript = ''
                vm.wait_for_unit("microvm@${hypervisor}-example.service")
              '';
            }) { inherit system; pkgs = nixpkgs.legacyPackages.${system}; };
            # Run a VM with to test MicroVM virtiofsd
            "vm-host-microvm-${hypervisor}-iperf" = import (nixpkgs + "/nixos/tests/make-test-python.nix") ({ ... }: {
              name = "vm-host-microvm-${hypervisor}-virtiofsd";
              nodes.vm = {
                imports = [ self.nixosModules.host ];
                microvm.vms."${hypervisor}-iperf-server".flake = self;
                environment.systemPackages = with nixpkgs.legacyPackages.${system}; [ iperf iproute ];
                virtualisation = {
                  # larger than the defaults
                  memorySize = 2048;
                  cores = 2;
                  # 9P performance optimization that quelches a qemu warning
                  msize = 65536;
                  # # allow building packages
                  # writableStore = true;
                  # # keep the store paths built inside the VM across reboots
                  # writableStoreUseTmpfs = false;
                  qemu.options = [ "-enable-kvm" ];
                };
              };
              testScript = ''
                vm.wait_for_unit("microvm@${hypervisor}-iperf-server.service")
                vm.succeed("ip addr add 10.0.0.2/24 dev microvm")
                result = vm.wait_until_succeeds("iperf -c 10.0.0.1")
                print(result)
              '';
            }) { inherit system; pkgs = nixpkgs.legacyPackages.${system}; };
          } // (
            let
              pkgs = nixpkgs.legacyPackages.${system};
              microvm = (nixpkgs.lib.nixosSystem {
                inherit system ;
                modules = [
                  self.nixosModules.microvm
                  {
                    networking.hostName = "microvm-test";
                    networking.useDHCP = false;
                    microvm.socket = "./microvm.sock";
                  }
                ];
              }).config.microvm.runner.${hypervisor};
            in nixpkgs.lib.optionalAttrs microvm.canShutdown {
              # Test the shutdown command
              "microvm-${hypervisor}-test-shutdown-command" =
                pkgs.runCommandNoCCLocal "microvm-${hypervisor}-test-shutdown-command" {
                } ''
                  set -m
                  ${microvm}/bin/microvm-run > $out &

                  sleep 10
                  echo Now shutting down
                  ${microvm}/bin/microvm-shutdown
                  fg
                '';
            }
          )) {} self.lib.hypervisors;
      }) // {
        lib = import ./lib { nixpkgs-lib = nixpkgs.lib; };

        overlay = final: prev: {
          kvmtool = prev.callPackage ./pkgs/kvmtool.nix {};
          microvm-kernel = prev.linuxPackages_latest.callPackage ./pkgs/microvm-kernel.nix {};
        };

        nixosModules = {
          microvm = import ./nixos-modules/microvm self;
          host = import ./nixos-modules/host.nix;
        };

        defaultTemplate = self.templates.microvm;
        templates.microvm = {
          path = ./flake-template;
          description = "Flake with MicroVMs";
        };

        nixosConfigurations =
          let
            makeExample = { system, hypervisor, config ? {} }:
              nixpkgs.lib.nixosSystem {
                inherit system;
                modules = [
                  self.nixosModules.microvm
                  {
                    networking.hostName = "${hypervisor}-microvm";
                    users.users.root.password = "";
                    services.getty.helpLine = ''
                      Log in as "root" with an empty password.
                    '';

                    microvm.hypervisor = hypervisor;
                    microvm.volumes = [ {
                      mountPoint = "/var";
                      image = "var.img";
                      size = 256;
                    } ];
                  }
                  config
                ];
              };
          in
            (builtins.foldl' (results: system:
              builtins.foldl' ({ result, n }: hypervisor: {
                result = result // {
                  "${system}-${hypervisor}-example" = makeExample {
                    inherit system hypervisor;
                  };

                  "${system}-${hypervisor}-example-with-tap" = makeExample {
                    inherit system hypervisor;
                    config = {
                      microvm.interfaces = [ {
                        type = "tap";
                        id = "vm-${builtins.substring 0 4 hypervisor}";
                        mac = "00:02:00:01:01:0${toString n}";
                      } ];
                      networking.interfaces.eth0.useDHCP = true;
                      networking.firewall.allowedTCPPorts = [ 22 ];
                      services.openssh = {
                        enable = true;
                        permitRootLogin = "yes";
                      };
                    };
                  };

                  # TODO: -iperf-server
                };
                n = n + 1;
              }) results self.lib.hypervisors
            ) { result = {}; n = 1; } systems).result;
      };
}
