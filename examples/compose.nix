{ self, lib }:

let
  microvm = self;

in
microvm.lib.compose.evalModules {
  modules = builtins.genList (n: {
    microvm.vms."qemu${toString n}".config = {
      microvm.hypervisor = "qemu";
    };
    # microvm.vms."chv${toString n}".config = {
    #   microvm.hypervisor = "cloud-hypervisor";
    # };
    # microvm.vms."firecracker${toString n}".config = {
    #   microvm.hypervisor = "firecracker";
    # };
  }) 1;
}
