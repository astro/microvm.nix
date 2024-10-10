{
  description = "Contain NixOS in a MicroVM";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    spectrum = {
      url = "git+https://spectrum-os.org/git/spectrum";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, spectrum }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # https://github.com/NixOS/nixpkgs/pull/296538
      # TODO: remove entirely after NixOS 24.05
      overrideWaypipe = pkgs:
        if builtins.compareVersions pkgs.waypipe.version "0.9" >= 0
        then pkgs.waypipe
        else pkgs.waypipe.overrideAttrs (attrs: rec {
          version = "0.9.0";
          src = pkgs.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "mstoeckl";
            repo = "waypipe";
            rev = "v${version}";
            hash = "sha256-zk5IzZiFff9EeJn24/QmE1ybcBkxpaz6Owp77CfCwV0=";
          };
        });
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
            qemu-vnc = nixosToApp ./examples/qemu-vnc.nix;
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

                ${pkgs.nix}/bin/nix run \
                  -f ${./examples/graphics.nix} \
                  config.microvm.declaredRunner \
                  --arg self 'builtins.getFlake "${self}"' \
                  --arg system '"${system}"' \
                  --arg nixpkgs 'builtins.getFlake "${nixpkgs}"' \
                  --arg packages "\"$*\"" \
                  --arg tapInterface "$TAP_INTERFACE"
              '');
            };
            # Run this on your host to accept Wayland connections
            # on AF_VSOCK.
            waypipe-client = {
              type = "app";
              program = toString (pkgs.writeShellScript "waypipe-client" ''
                exec ${self.packages.${system}.waypipe}/bin/waypipe --vsock -s 6000 client
              '');
            };
          };

        packages =
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ self.overlay ];
            };
          in {
            build-microvm = pkgs.callPackage ./pkgs/build-microvm.nix { inherit self; };
            doc = pkgs.callPackage ./pkgs/doc.nix { inherit nixpkgs; };
            microvm = import ./pkgs/microvm-command.nix {
              pkgs = import nixpkgs { inherit system; };
            };
            # all compilation-heavy packages that shall be prebuilt for a binary cache
            prebuilt = pkgs.buildEnv {
              name = "prebuilt";
              paths = with self.packages.${system}; with pkgs; [
                qemu-example
                cloud-hypervisor-example
                firecracker-example
                crosvm-example
                kvmtool-example
                stratovirt-example
                # alioth-example
                virtiofsd
              ];
              pathsToLink = [ "/" ];
              extraOutputsToInstall = [ "dev" ];
              ignoreCollisions = true;
            };
            waypipe = overrideWaypipe pkgs;
            alioth = pkgs.callPackage ./pkgs/alioth.nix {};
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

        # Takes too much memory in `nix flake show`
        # checks = import ./checks { inherit self nixpkgs system; };

        # hydraJobs are checks
        hydraJobs = builtins.mapAttrs (_: check:
          (nixpkgs.lib.recursiveUpdate check {
            meta.timeout = 12 * 60 * 60;
          })
        ) (import ./checks { inherit self nixpkgs system; });
      }) // {
        lib = import ./lib { inherit (nixpkgs) lib; };

        overlay = final: prev: {
          cloud-hypervisor-graphics = prev.callPackage (spectrum + "/pkgs/cloud-hypervisor") {};
          waypipe = overrideWaypipe prev;
          alioth = prev.callPackage ./pkgs/alioth.nix {};
        };
        overlays.default = self.overlay;

        nixosModules = {
          microvm = import ./nixos-modules/microvm;
          host = import ./nixos-modules/host;
          # Just the generic microvm options
          microvm-options = import ./nixos-modules/microvm/options.nix;
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
                    services.getty.autologinUser = "root";

                    nixpkgs.overlays = [ self.overlay ];
                    microvm.hypervisor = hypervisor;
                    # share the host's /nix/store if the hypervisor can do 9p
                    microvm.shares = lib.optional (builtins.elem hypervisor hypervisorsWith9p) {
                      tag = "ro-store";
                      source = "/nix/store";
                      mountPoint = "/nix/.ro-store";
                    };
                    # microvm.writableStoreOverlay = "/nix/.rw-store";
                    # microvm.volumes = [ {
                    #   image = "nix-store-overlay.img";
                    #   mountPoint = config.microvm.writableStoreOverlay;
                    #   size = 2048;
                    # } ];
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
                    config = { lib, ...}: {
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
