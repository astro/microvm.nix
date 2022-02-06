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
            kvmtool = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/kvmtool.nix {};
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
