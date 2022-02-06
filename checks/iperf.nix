{ self, nixpkgs, system, hypervisor }:

nixpkgs.lib.optionalAttrs (builtins.elem hypervisor self.lib.hypervisorsWithNetwork) {
  # Run a VM with to test MicroVM virtiofsd
  "vm-${hypervisor}-iperf" = import (nixpkgs + "/nixos/tests/make-test-python.nix") ({ ... }: {
    name = "vm-host-microvm-${hypervisor}-virtiofsd";
    nodes.vm = {
      imports = [ self.nixosModules.host ];
      microvm.vms."${system}-${hypervisor}-iperf-server".flake = self;
      environment.systemPackages = with nixpkgs.legacyPackages.${system}; [ iperf iproute ];
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
        qemu.options = [ "-enable-kvm" ];
      };
    };
    testScript = ''
      vm.wait_for_unit("microvm@${hypervisor}-iperf-server.service")
      vm.succeed("ip addr add 10.0.0.2/24 dev microvm")
      result = vm.wait_until_succeeds("iperf -c 10.0.0.1")
      print(result)
    '';
  }) { inherit system; pkgs = nixpkgs.legacyPackages.${system}; };
}
