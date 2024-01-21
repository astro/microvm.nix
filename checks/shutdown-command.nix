{ self, nixpkgs, system, makeTestConfigs }:

let
  pkgs = nixpkgs.legacyPackages.${system};

  configs = makeTestConfigs {
    name = "shutdown-command";
    inherit system;
    modules = [
      ({ config, lib, ... }: {
        networking = {
          hostName = "microvm-test";
          useDHCP = false;
        };
        microvm = {
          socket = "./microvm.sock";
          crosvm.pivotRoot = "/build/empty";
          testing.enableTest = config.microvm.declaredRunner.canShutdown;
        };
        system.stateVersion = lib.mkDefault lib.trivial.release;
      })
    ];
  };

in
builtins.mapAttrs (_: nixos:
  pkgs.runCommandLocal "microvm-test-shutdown-command" {
    nativeBuildInputs = [
      nixos.config.microvm.declaredRunner
      pkgs.p7zip
    ];
    requiredSystemFeatures = [ "kvm" ];
    meta.timeout = 120;
  } ''
    set -m
    microvm-run > $out &
    export MAINPID=$!

    sleep 30
    echo Now shutting down
    microvm-shutdown
  ''
) configs
