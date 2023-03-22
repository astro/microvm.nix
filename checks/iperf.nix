{ self, nixpkgs, system, hypervisor }:

nixpkgs.lib.optionalAttrs (builtins.elem hypervisor self.lib.hypervisorsWithNetwork) {
  # Run a VM with to test MicroVM virtiofsd
  "vm-${hypervisor}-iperf" = import (nixpkgs + "/nixos/tests/make-test-python.nix") ({ pkgs, ... }: {
    name = "vm-${hypervisor}-iperf";
    nodes.vm = {
      imports = [ self.nixosModules.host ];
      microvm.vms."${hypervisor}-iperf-server".flake = nixpkgs.legacyPackages.${system}.runCommand "${hypervisor}-iperf-server.flake" {
        passthru.nixosConfigurations."${hypervisor}-iperf-server" = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.microvm
            {
              microvm = {
                hypervisor = hypervisor;
                interfaces = [ {
                  type = "tap";
                  id = "microvm";
                  mac = "00:02:00:01:01:01";
                } ];
              };
              networking.hostName = "${hypervisor}-microvm";
              networking = {
                interfaces.eth0 = {
                  useDHCP = false;
                  ipv4.addresses = [ {
                    address = "10.0.0.1";
                    prefixLength = 24;
                  } ];
                };
                firewall.enable = false;
              };
              services.iperf3.enable = true;
            }
          ];
        };
      } "touch $out";
      environment.systemPackages = with pkgs; [ #with nixpkgs.legacyPackages.${system}; [
        iperf iproute
      ];
      virtualisation = {
        # larger than the defaults
        memorySize = 2048;
        cores = 2;
        # 9P performance optimization that quelches a qemu warning
        msize = 65536;
        # # allow building packages
        # writableStore = true;
        # # keep the store paths built inside the VM across reboots
        # writableStoreUseTmpfs = false;
        qemu.options = [
          "-cpu"
          {
            "aarch64-linux" = "cortex-a72";
            "x86_64-linux" = "kvm64,+svm,+vmx";
          }.${system}
        ];
      };
    };
    testScript = ''
      vm.wait_for_unit("microvm@${hypervisor}-iperf-server.service")
      vm.succeed("ip addr add 10.0.0.2/24 dev microvm")
      result = vm.wait_until_succeeds("iperf -c 10.0.0.1", 60)
      print(result)
    '';
    meta.timeout = 1800;
  }) { inherit system; pkgs = nixpkgs.legacyPackages.${system}; };
}
