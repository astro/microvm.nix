{ self, lib }:

let
  microvm = self;

in
microvm.lib.compose.evalModules {
  modules = [ {
    microvm.vms.foo.config = {
    };
    microvm.vms.bar.config = {
    };
  } ];
}
