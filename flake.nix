{
  description = "Contain NixOS in a MicroVM";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
      flake-utils.lib.eachSystem systems (system: {

        apps =
          let
            pkgs = nixpkgs.legacyPackages.${system};
            nixosToApp = configFile: {
              type = "app";
              program = "${(import configFile {
                inherit self nixpkgs system;
              }).config.microvm.declaredRunner}/bin/microvm-run";
            };
          in {
            vm = nixosToApp ./examples/microvms-host.nix;
            graphics = {
              type = "app";
              program = toString (pkgs.writeShellScript "run-graphics" ''
                set -e

                if [ -z "$*" ]; then
                  echo "Usage: $0 [--tap tap0] <pkgs...>"
                  exit 1
                fi

                if [ "$1" = "--tap" ]; then
                  TAP_INTERFACE="\"$2\""
                  shift 2
                else
                  TAP_INTERFACE=null
                fi

                RUNNER=$(${pkgs.nix}/bin/nix build \
                  -f ${./examples/graphics.nix} \
                  config.microvm.declaredRunner \
                  --arg self 'builtins.getFlake "${self}"' \
                  --arg system '"${system}"' \
                  --arg nixpkgs 'builtins.getFlake "${nixpkgs}"' \
                  --arg packages "\"$*\"" \
                  --arg tapInterface "$TAP_INTERFACE" \
                  --no-link --print-out-paths)
                exec $RUNNER/bin/microvm-run
              '');
            };
          };

        packages =
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in {
            build-microvm = pkgs.callPackage ./pkgs/build-microvm.nix { inherit self; };
            doc = pkgs.callPackage ./pkgs/doc.nix { inherit nixpkgs; };
            mktuntap = pkgs.callPackage ./pkgs/mktuntap.nix {};
            microvm-kernel = pkgs.linuxPackages_latest.callPackage ./pkgs/microvm-kernel.nix {};
            microvm = import ./pkgs/microvm-command.nix {
              inherit pkgs;
            };
            # all compilation-heavy packages that shall be prebuilt for a binary cache
            prebuilt = pkgs.buildEnv {
              name = "prebuilt";
              paths = with self.packages.${system}; with pkgs; [
                qemu_kvm cloud-hypervisor
                firectl firecracker
                crosvm kvmtool
                microvm-kernel virtiofsd
              ];
              pathsToLink = [ "/" ];
              extraOutputsToInstall = [ "dev" ];
            };
            cloud-hypervisor-graphics = pkgs.callPackage ./pkgs/spectrum-os/cloud-hypervisor {};
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

        checks = import ./checks { inherit self nixpkgs system; };

        # hydraJobs are checks
        hydraJobs = builtins.mapAttrs (_: check:
          with nixpkgs.lib;
          hydraJob (recursiveUpdate check {
            meta.timeout = 12 * 60 * 60;
          })
        ) self.checks.${system};
      }) // {
        lib = import ./lib { nixpkgs-lib = nixpkgs.lib; };

        overlay = final: prev: {
          microvm-kernel = prev.linuxPackages_latest.callPackage ./pkgs/microvm-kernel.nix {};
          cloud-hypervisor-graphics = prev.callPackage ./pkgs/spectrum-os/cloud-hypervisor {};
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
            hypervisorsWith9p = [
              "qemu"
              # currently broken:
              # "crosvm"
            ];
            hypervisorsWithUserNet = [ "qemu" "kvmtool" ];
            makeExample = { system, hypervisor, config ? {} }:
              nixpkgs.lib.nixosSystem {
                inherit system;
                modules = [
                  self.nixosModules.microvm
                  ({ config, lib, ... }: {
                    system.stateVersion = config.system.nixos.version;

                    networking.hostName = "${hypervisor}-microvm";
                    users.users.root.password = "";
                    services.getty.helpLine = ''
                      Log in as "root" with an empty password.
                    '';

                    microvm.hypervisor = hypervisor;
                    # share the host's /nix/store if the hypervisor can do 9p
                    microvm.shares = lib.optional (builtins.elem hypervisor hypervisorsWith9p) {
                      tag = "ro-store";
                      source = "/nix/store";
                      mountPoint = "/nix/.ro-store";
                    };
                    microvm.writableStoreOverlay = "/nix/.rw-store";
                    microvm.volumes = [ {
                      image = "nix-store-overlay.img";
                      mountPoint = config.microvm.writableStoreOverlay;
                      size = 2048;
                    } ];
                    microvm.interfaces = lib.optional (builtins.elem hypervisor hypervisorsWithUserNet) {
                      type = "user";
                      id = "qemu";
                      mac = "02:00:00:01:01:01";
                    };
                    microvm.forwardPorts = lib.optional (hypervisor == "qemu") {
                      host.port = 2222;
                      guest.port = 22;
                    };
                    networking.firewall.allowedTCPPorts = lib.optional (hypervisor == "qemu") 22;
                    services.openssh = lib.optionalAttrs (hypervisor == "qemu") {
                      enable = true;
                      settings.PermitRootLogin = "yes";
                    };
                  })
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
                } //
                nixpkgs.lib.optionalAttrs (builtins.elem hypervisor self.lib.hypervisorsWithNetwork) {
                  "${system}-${hypervisor}-example-with-tap" = makeExample {
                    inherit system hypervisor;
                    config = {
                      microvm.interfaces = [ {
                        type = "tap";
                        id = "vm-${builtins.substring 0 4 hypervisor}";
                        mac = "02:00:00:01:01:0${toString n}";
                      } ];
                      networking.interfaces.eth0.useDHCP = true;
                      networking.firewall.allowedTCPPorts = [ 22 ];
                      services.openssh = {
                        enable = true;
                        settings.PermitRootLogin = "yes";
                      };
                    };
                  };
                };
                n = n + 1;
              }) results self.lib.hypervisors
            ) { result = {}; n = 1; } systems).result;
      };
}
