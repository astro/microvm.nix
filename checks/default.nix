{ self, nixpkgs, system }:

builtins.foldl' (result: hypervisor:
  let
    args = {
      inherit self nixpkgs system hypervisor;
    };
  in
    result //
    import ./startup-shutdown.nix args //
    import ./shutdown-command.nix args //
    import ./vm.nix args //
    import ./iperf.nix args
) {} self.lib.hypervisors
