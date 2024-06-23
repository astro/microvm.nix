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
            image = "output.img";
            label = "output";
            mountPoint = "/output";
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
                stratovirt = "reboot";
              }.${config.microvm.hypervisor};
            in ''
              ${pkgs.coreutils}/bin/uname > /output/kernel-name
              ${pkgs.coreutils}/bin/uname -m > /output/machine-name

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
  } (let
    expectedMachineName = (crossSystem:
      if crossSystem == null then
        expectedMachineName { config = system; }
      else if crossSystem.config == "aarch64-unknown-linux-gnu" then
        "aarch64"
      else if crossSystem.config == "x86_64-linux" then
        "x86_64"
      else throw "unknown machine name (${crossSystem.config})"
    );
  in ''
    microvm-run

    7z e output.img kernel-name machine-name

    EXPECTED_KERNEL_NAME="Linux"
    if [ "$(cat kernel-name)" != "$EXPECTED_KERNEL_NAME" ] ; then
      echo "Kernel does not match (got: $(cat kernel-name); expected: $EXPECTED_KERNEL_NAME)"
      exit 1
    fi

    EXPECTED_MACHINE_NAME="${expectedMachineName nixos.config.nixpkgs.crossSystem}"
    if [ "$(cat machine-name)" != "$EXPECTED_MACHINE_NAME" ] ; then
      echo "Machine does not match (got: $(cat machine-name); expected: $EXPECTED_MACHINE_NAME)"
      exit 1
    fi

    mkdir $out
    cp {kernel-name,machine-name} $out
  '')
) configs
