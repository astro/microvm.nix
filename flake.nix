{
  description = "Contain NixOS in a MicroVM";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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
            kvmtool = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/kvmtool.nix {};
            virtiofsd = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/virtiofsd.nix {};
            microvm-kernel = nixpkgs.legacyPackages.${system}.linuxPackages_latest.callPackage ./pkgs/microvm-kernel.nix {};
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

        checks = import ./checks { inherit self nixpkgs system; };
      }) // {
        lib = import ./lib { nixpkgs-lib = nixpkgs.lib; };

        overlay = _final: prev: {
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
            hypervisorsWith9p = [ "qemu" "crosvm" "kvmtool" ];
            makeExample = { system, hypervisor, config ? {} }:
              nixpkgs.lib.nixosSystem {
                inherit system;
                modules = [
                  self.nixosModules.microvm
                  ({ config, lib, ... }: {
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
                    microvm.volumes = [ {
                      image = "nix-store-overlay.img";
                      mountPoint = config.microvm.writableStoreOverlay;
                      size = 2048;
                    } ];
                    microvm.interfaces = lib.optional (hypervisor == "qemu") {
                      type = "user";
                      id = "qemu";
                      mac = "00:02:00:01:01:01";
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
                };
                n = n + 1;
              }) results self.lib.hypervisors
            ) { result = {}; n = 1; } systems).result;
      };
}
