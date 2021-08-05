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
            makeExample = { hypervisor, ... }@args:
              self.lib.runner (nixpkgs.lib.recursiveUpdate {
                inherit system;
                nixosConfig = {
                  networking.hostName = "${hypervisor}-microvm";
                  users.users.root.password = "";
                };
                volumes = [ {
                  mountpoint = "/var";
                  image = "var.img";
                  size = 256;
                } ];
                shares = [ {
                  socket = "/tmp/x.sock";
                  tag = "x";
                  mountpoint = "/var";
                  source = "/tmp/x";
                } ];
              } args);
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
          in
            {
              qemu-example = makeExample { hypervisor = "qemu"; };
              firecracker-example = makeExample { hypervisor = "firecracker"; };
              cloud-hypervisor-example = makeExample { hypervisor = "cloud-hypervisor"; };
              crosvm-example = makeExample { hypervisor = "crosvm"; };

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

              microvm = import ./pkgs/microvm-command.nix {
                pkgs = nixpkgs.legacyPackages.${system};
              };
            };

        checks =
          builtins.foldl' (result: hypervisor: result // {
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
        lib = (
          import ./lib {
            nixpkgs-lib = nixpkgs.lib;
          }
        ) // {
          inherit (import ./lib/disk-image.nix {
            inherit self nixpkgs;
          }) mkDiskImage;

          hypervisors = builtins.mapAttrs (hypervisor: path: (
            import path {
              inherit self nixpkgs;
            }
          )) {
            qemu = ./lib/hypervisors/qemu.nix;
            firecracker = ./lib/hypervisors/firecracker.nix;
            cloud-hypervisor = ./lib/hypervisors/cloud-hypervisor.nix;
            crosvm = ./lib/hypervisors/crosvm.nix;
          };

          makeMicrovm =
            { hypervisor
            , system
            , nixosConfig
            , extraArgs ? {}
            , vcpu ? 1
            , mem ? 512
            , append ? ""
            , volumes ? []
            , shares ? []
            , ... }@args:
            let
              pkgs = nixpkgs.legacyPackages.${system};

              config = args // {
                inherit vcpu mem append;
                inherit (config.nixos.config.networking) hostName;
                volumes = map ({ letter, ... }@volume: volume // {
                  device = "/dev/vd${letter}";
                }) (self.lib.withDriveLetters 1 volumes);

                rootDisk = self.lib.mkDiskImage {
                  inherit (config) system nixos hostName;
                };

                nixos = nixpkgs.lib.nixosSystem {
                  inherit system;
                  extraArgs = extraArgs // {
                    inherit (config.rootDisk.passthru) writablePaths;
                    microvm = config;
                  };
                  modules = [
                    self.nixosModules.microvm
                    nixosConfig
                  ];
                };

                canShutdown = false;
                shutdownCommand = throw "Shutdown not implemented for ${hypervisor}";
              };

              extend = { command, preStart ? "", hostName, volumes, shares, interfaces, canShutdown, shutdownCommand, ... }@args:
                args // rec {
                  run = ''
                    #! ${pkgs.runtimeShell} -e

                    ${self.lib.createVolumesScript pkgs volumes}
                    ${preStart}

                    exec ${command}
                  '';
                  runScript = pkgs.writeScript "run-${hypervisor}-${hostName}" run;
                  runScriptBin = pkgs.writeScriptBin "microvm-run" run;

                  shutdown = ''
                    #! ${pkgs.runtimeShell} -e

                    ${shutdownCommand}
                  '';
                  shutdownScript = pkgs.writeScript "shutdown-${hypervisor}-${hostName}" shutdown;
                  shutdownScriptBin = pkgs.writeScriptBin "microvm-shutdown" shutdown;

                  runner = nixpkgs.legacyPackages.${system}.runCommand "microvm-run" {
                    passthru = result;
                  } ''
                    mkdir -p $out/bin

                    ln -s ${runScriptBin}/bin/microvm-run $out/bin/microvm-run
                    ${if canShutdown
                      then "ln -s ${shutdownScriptBin}/bin/microvm-shutdown $out/bin/microvm-shutdown"
                      else ""}

                    mkdir -p $out/share/microvm
                    echo "${nixpkgs.lib.concatMapStringsSep " " (interface:
                      if interface.type == "tap" && interface ? id
                      then interface.id
                      else ""
                    ) interfaces}" > $out/share/microvm/tap-interfaces
                    ${nixpkgs.lib.optionalString (shares != []) (
                      nixpkgs.lib.concatMapStringsSep "\n" ({ tag, socket, source, ... }: ''
                        mkdir -p $out/share/microvm/virtiofs/${tag}
                        echo "${socket}" > $out/share/microvm/virtiofs/${tag}/socket
                        echo "${source}" > $out/share/microvm/virtiofs/${tag}/source
                      '') shares
                    )}
                  '';
                };
              result = extend (
                self.lib.hypervisors.${hypervisor} config
              );
            in result;

          runner = args: (
            self.lib.makeMicrovm args
          ).runner;
        };

        nixosModules = {
          microvm = import ./nixos-modules/microvm.nix;
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
