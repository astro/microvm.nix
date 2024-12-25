{ self, nixpkgs, system, hypervisor }:

{
  # Run a VM with a MicroVM
  "vm-${hypervisor}" = import (nixpkgs + "/nixos/tests/make-test-python.nix") ({ ... }: {
    name = "vm-${hypervisor}";
    nodes.vm = {
      imports = [ self.nixosModules.host ];

      virtualisation.qemu.options = [
        "-cpu"
        {
          "aarch64-linux" = "cortex-a72";
          "x86_64-linux" = "kvm64,+svm,+vmx";
        }.${system}
      ];
      # Must be big enough for the store overlay volume
      virtualisation.diskSize = 4096;
      # Hack for slow Github CI
      systemd.extraConfig = ''
        DefaultTimeoutStartSec=600
      '';

      microvm.vms."${system}-${hypervisor}-example".flake = self;
    };
    testScript = ''
      vm.wait_for_unit("microvm@${system}-${hypervisor}-example.service", timeout = 1200)
    '';
    meta.timeout = 1800;
  }) { inherit system; pkgs = nixpkgs.legacyPackages.${system}; };
}
