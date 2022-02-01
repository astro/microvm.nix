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
                inherit (self.nixosConfigurations.microvms-host) config;
              in
                "${config.system.build.vm}/bin/run-${config.networking.hostName}-vm";
          };
        };

        packages =
          let
            makeExample = { hypervisor, nixosConfig ? {}, interfaces ? [] }:
              (nixpkgs.lib.nixosSystem {
                inherit system;
                modules = [
                  self.nixosModules.microvm
                  {
                    networking.hostName = "${hypervisor}-microvm";
                    users.users.root.password = "";

                    microvm.interfaces = interfaces;
                    microvm.volumes = [ {
                      mountPoint = "/var";
                      image = "var.img";
                      size = 256;
                    } ];
                    # shares = [ {
                    #   socket = "/tmp/x.sock";
                    #   tag = "x";
                    #   mountPoint = "/var";
                    #   source = "/tmp/x";
                    # } ];
                  }
                  nixosConfig
                ];
              }).config.microvm.runner.${hypervisor};

            makeExampleWithTap = args:
              makeExample (nixpkgs.lib.recursiveUpdate {
                nixosConfig = {
                  networking.interfaces.eth0.useDHCP = true;
                  networking.firewall.allowedTCPPorts = [ 22 ];
                  services.openssh = {
                    enable = true;
                    permitRootLogin = "yes";
                  };
                };
              } args);

            makeIperfServer = args: makeExampleWithTap ({
              interfaces = [ {
                type = "tap";
                id = "microvm";
                mac = "00:02:00:01:01:01";
              } ];
              nixosConfig = {
                networking = {
                  interfaces.eth0 = {
                    useDHCP = false;
                    ipv4.addresses = [ {
                      address = "10.0.0.1";
                      prefixLength = 24;
                    } ];
                  };
                  firewall.enable = false;
                };
                services.iperf3.enable = true;
              };
            } // args);
          in
            {
              qemu-example = makeExample { hypervisor = "qemu"; };
              firecracker-example = makeExample { hypervisor = "firecracker"; };
              cloud-hypervisor-example = makeExample { hypervisor = "cloud-hypervisor"; };
              crosvm-example = makeExample { hypervisor = "crosvm"; };
              kvmtool-example = makeExample { hypervisor = "kvmtool"; };

              qemu-example-with-tap = makeExampleWithTap {
                hypervisor = "qemu";
                interfaces = [ {
                  type = "tap";
                  id = "qemu-eth0";
                  mac = "00:02:00:01:01:01";
                } ];
              };
              firecracker-example-with-tap = makeExampleWithTap {
                hypervisor = "firecracker";
                interfaces = [ {
                  type = "tap";
                  id = "fire-eth0";
                  mac = "00:02:00:01:01:02";
                } ];
              };
              cloud-hypervisor-example-with-tap = makeExampleWithTap {
                hypervisor = "cloud-hypervisor";
                interfaces = [ {
                  type = "tap";
                  id = "cloud-eth0";
                  mac = "00:02:00:01:01:03";
                } ];
              };
              kvmtool-example-with-tap = makeExampleWithTap {
                hypervisor = "kvmtool";
                interfaces = [ {
                  type = "tap";
                  id = "kvmtool-eth0";
                  mac = "00:02:00:01:01:05";
                } ];
              };

              qemu-iperf-server = makeIperfServer {
                hypervisor = "qemu";
              };
              firecracker-iperf-server = makeIperfServer {
                hypervisor = "firecracker";
              };
              cloud-hypervisor-iperf-server = makeIperfServer {
                hypervisor = "cloud-hypervisor";
              };

              microvm = import ./pkgs/microvm-command.nix {
                pkgs = nixpkgs.legacyPackages.${system};
              };
            };

        _checks =
          builtins.foldl' (result: hypervisor: result // {
            # Run a MicroVM that immediately shuts down again
            "microvm-${hypervisor}-test-startup-shutdown" =
              let
                pkgs = nixpkgs.legacyPackages.${system};
                microvm = self.lib.makeMicrovm {
                  inherit system hypervisor;
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
                            kvmtool = "reboot";
                          }.${hypervisor};
                        in ''
                          ${pkgs.coreutils}/bin/uname > /var/OK
                          ${exit}
                        '';
                    };
                  };
                  volumes = [ {
                    mountPoint = "/var";
                    image = "var.img";
                    size = 32;
                  } ];
                };
              in pkgs.runCommandNoCCLocal "microvm-${hypervisor}-test-startup-shutdown" {
                buildInputs = [
                  microvm.runner
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
              microvm = self.lib.makeMicrovm {
                inherit system hypervisor;
                nixosConfig = {
                  networking.hostName = "microvm-test";
                  networking.useDHCP = false;
                };
                socket = "./microvm.sock";
              };
            in nixpkgs.lib.optionalAttrs microvm.canShutdown {
              # Test the shutdown command
              "microvm-${hypervisor}-test-shutdown-command" =
                pkgs.runCommandNoCCLocal "microvm-${hypervisor}-test-shutdown-command" {
                } ''
                  set -m
                  ${microvm.runScript} > $out &

                  sleep 10
                  echo Now shutting down
                  ${microvm.shutdownCommand}
                  fg
                '';
            }
          )) {} (builtins.attrNames self.lib.hypervisors);
      }) // {
        lib = import ./lib { nixpkgs-lib = nixpkgs.lib; };

        overlay = final: prev: {
          kvmtool = prev.callPackage ./pkgs/kvmtool.nix {};
        };

        nixosModules = {
          microvm = import ./nixos-modules/microvm self;
          host = import ./nixos-modules/host.nix;
        };

        nixosConfigurations.microvms-host = import ./examples/microvms-host.nix {
          inherit self nixpkgs;
          system = "x86_64-linux";
        };

        defaultTemplate = self.templates.microvm;
        templates.microvm = {
          path = ./flake-template;
          description = "Flake with MicroVMs";
        };
      };
}
