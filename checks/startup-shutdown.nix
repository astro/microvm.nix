{ self, nixpkgs, system, hypervisor }:

{
  # Run a MicroVM that immediately shuts down again
  "${hypervisor}-startup-shutdown" =
    let
      pkgs = nixpkgs.legacyPackages.${system};
      microvm = (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.microvm
          ({ pkgs, ... }: {
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
            microvm.volumes = [ {
              mountPoint = "/var";
              image = "var.img";
              size = 32;
            } ];
          })
        ];
      }).config.microvm.runner.${hypervisor};
    in pkgs.runCommandNoCCLocal "microvm-${hypervisor}-test-startup-shutdown" {
      buildInputs = [
        microvm
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
}
