{ self, nixpkgs }:

{ system
, hostName
, vcpu
, mem
, nixos
, append
, interfaces ? []
, rootDisk
, volumes ? []
, preStart ? ""
, ...
}@args:
let
  config = args // {
    inherit interfaces;
  };
in config // {
  preStart = ''
    ${preStart}
    export HOME=$PWD
  '';

  command = nixpkgs.lib.escapeShellArgs (
    [
      "${self.packages.${system}.kvmtool}/bin/lkvm" "run"
      "--name" hostName
      "-m" (toString mem)
      "-c" (toString vcpu)
      "-d" "${rootDisk},ro"
      "--console" "virtio"
      "--rng"
      "-k" "${nixos.config.system.build.kernel}/bzImage"
      "-p" "console=ttyS0 quiet reboot=k panic=1 nomodules ro init=${nixos.config.system.build.toplevel}/init ${append}"
    ] ++
    builtins.concatMap ({ image, ... }:
      [ "-d" image ]
    ) volumes ++
    # TODO:
    # map (_:
    #   throw "virtiofs shares not implemented for kvmtool"
    # ) shares ++
    builtins.concatMap ({ type, id, mac, ... }:
      [ "-n" "mode=${type},tapif=${id},guest_mac=${mac}" ]
    ) interfaces
  );

  # `lkvm stop` works but is not graceful.
  canShutdown = false;
}
