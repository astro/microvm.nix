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

        packages = {
          microvm = import ./pkgs/microvm-command.nix {
            pkgs = nixpkgs.legacyPackages.${system};
          };

          qemu-example = self.lib.runner {
            inherit system;
            hypervisor = "qemu";
            nixosConfig = {
              networking.hostName = "microvm";
              users.users.root.password = "";
            };
            volumes = [ {
              mountpoint = "/var";
              image = "var.img";
              size = 256;
            } ];
          };

          firecracker-example = self.lib.runner {
            inherit system;
            hypervisor = "firecracker";
            nixosConfig = {
              networking.hostName = "microvm";
              users.users.root.password = "";
            };
            volumes = [ {
              mountpoint = "/var";
              image = "var.img";
              size = 256;
            } ];
          };

          cloud-hypervisor-example = self.lib.runner {
            inherit system;
            hypervisor = "cloud-hypervisor";
            nixosConfig = {
              networking.hostName = "microvm";
              users.users.root.password = "";
            };
            volumes = [ {
              mountpoint = "/var";
              image = "var.img";
              size = 256;
            } ];
          };

          crosvm-example = self.lib.runner {
            inherit system;
            hypervisor = "crosvm";
            nixosConfig = {
              networking.hostName = "microvm";
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
            , vcpu ? 1
            , mem ? 512
            , append ? ""
            , rootReserve ? "64M"
            , volumes ? []
            , ... }@args:
            let
              pkgs = nixpkgs.legacyPackages.${system};

              config = args // {
                inherit vcpu mem append rootReserve;
                inherit (config.nixos.config.networking) hostName;
                volumes = map ({ letter, ... }@volume: volume // {
                  device = "/dev/vd${letter}";
                }) (self.lib.withDriveLetters 1 volumes);

                rootDisk = self.lib.mkDiskImage {
                  inherit (config) system rootReserve nixos hostName;
                };

                nixos = nixpkgs.lib.nixosSystem {
                  inherit system;
                  extraArgs = {
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

              extend = { command, preStart ? "", hostName, volumes, canShutdown, shutdownCommand, ... }@args:
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

        nixosConfigurations.microvms-host = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            self.nixosModules.host
            ({ pkgs, lib, options, config, ... }: {
              networking.hostName = "microvms-host";
              users.users.root.password = "";
              nix = {
                package = pkgs.nixFlakes;
                extraOptions = "experimental-features = nix-command flakes";
                registry = {
                  nixpkgs.flake = nixpkgs;
                  microvm.flake = self;
                };
              };
              environment.systemPackages = [
                pkgs.git
              ];
              services = let
                service = if lib.versionAtLeast (lib.versions.majorMinor lib.version) "20.09" then "getty" else "mingetty";
              in {
                ${service}.helpLine = ''
                  Log in as "root" with an empty password.
                  Type Ctrl-a c to switch to the qemu console
                  and `quit` to stop the VM.
                '';
              };
              virtualisation = lib.optionalAttrs (options.virtualisation ? qemu) {
                # larger than the defaults
                memorySize = 8192;
                cores = 12;
                diskSize = 8192;
                # 9P performance optimization that quelches a qemu warning
                msize = 65536;
                # allow building packages
                writableStore = true;
                # # keep the store paths built inside the VM across reboots
                # writableStoreUseTmpfs = false;

                qemu.options = [
                  # faster virtio-console
                  "-serial null"
                  "-device virtio-serial"
                  "-chardev stdio,mux=on,id=char0,signal=off"
                  "-mon chardev=char0,mode=readline"
                  "-device virtconsole,chardev=char0,nr=0"
                ];

                # use virtio's hvc0 as system console
                qemu.consoles = ["tty0" "hvc0"];

                # headless qemu
                graphics = false;
              };

              microvm.vms.qemu-example = {
                flake = self;
              };
              microvm.vms.firecracker-example = {
                flake = self;
              };
              microvm.vms.cloud-hypervisor-example = {
                flake = self;
              };
              microvm.vms.crosvm-example = {
                flake = self;
              };
            })
          ];
        };

        defaultTemplate = self.templates.microvm;
        templates.microvm = {
          path = ./flake-template;
          description = "Flake with MicroVMs";
        };
      };
}
