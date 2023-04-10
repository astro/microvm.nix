{ self, nixpkgs, system, makeTestConfigs }:

let
  pkgs = nixpkgs.legacyPackages.${system};

  configs = makeTestConfigs {
    name = "startup-shutdown";
    inherit system;
    modules = [
      # Run a MicroVM that immediately shuts down again
      ({ config, lib, pkgs, ... }: {
        networking = {
          hostName = "microvm-test";
          useDHCP = false;
        };
        microvm = {
          volumes = [ {
            mountPoint = "/var";
            image = "var.img";
            size = 32;
          } ];
          crosvm.pivotRoot = "/build/empty";
        };
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
              }.${config.microvm.hypervisor};
            in ''
              ${pkgs.coreutils}/bin/uname > /var/OK
              ${exit}
            '';
        };
        system.stateVersion = lib.mkDefault lib.trivial.release;
      })
    ];
  };

in
builtins.mapAttrs (_: nixos:
  pkgs.runCommandLocal "microvm-test-startup-shutdown" {
    nativeBuildInputs = [
      nixos.config.microvm.declaredRunner
      pkgs.p7zip
    ];
    requiredSystemFeatures = [ "kvm" ];
    meta.timeout = 120;
  } ''
    microvm-run

    7z e var.img OK
    if [ "$(cat OK)" != "Linux" ] ; then
      echo Output does not match
      exit 1
    fi
    cp OK $out
  ''
) configs
