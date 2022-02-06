{ self, nixpkgs, system, hypervisor }:

{
  # Run a VM with a MicroVM
  "vm-${hypervisor}" = import (nixpkgs + "/nixos/tests/make-test-python.nix") ({ ... }: {
    name = "vm-host-microvm-${hypervisor}";
    nodes.vm = {
      imports = [ self.nixosModules.host ];
      microvm.vms."${hypervisor}-example".flake = self;
    };
    testScript = ''
      vm.wait_for_unit("microvm@${hypervisor}-example.service")
    '';
  }) { inherit system; pkgs = nixpkgs.legacyPackages.${system}; };
}
