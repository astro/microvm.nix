{ self, nixpkgs, system, hypervisor }:

{
  # Run a VM with a MicroVM
  "vm-${hypervisor}" = import (nixpkgs + "/nixos/tests/make-test-python.nix") ({ ... }: {
    name = "vm-${hypervisor}";
    nodes.vm = {
      imports = [ self.nixosModules.host ];
      virtualisation.qemu.options = [ "-cpu" "kvm64,vmx=on" ];
      microvm.vms."${system}-${hypervisor}-example".flake = self;
    };
    testScript = ''
      vm.wait_for_unit("microvm@${system}-${hypervisor}-example.service")
    '';
    meta.timeout = 1800;
  }) { inherit system; pkgs = nixpkgs.legacyPackages.${system}; };
}
