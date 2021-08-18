{ self, nixpkgs }:

{ system
, vcpu
, mem
, nixos
, append
, interfaces ? []
, rootDisk
, volumes ? []
, shares ? []
, ...
}@args:
let
  config = args // {
    inherit interfaces;
  };
  pkgs = nixpkgs.legacyPackages.${system};
in config // {
  command = nixpkgs.lib.escapeShellArgs (
    [
      "${self.packages.${system}.kvmtool}/bin/lkvm" "run"
      "-m" (toString mem)
      "-c" (toString vcpu)
      "-d" "${rootDisk},ro"
      "--console" "virtio"
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
    builtins.concatMap ({ type, id, ... }:
      [ "-n" "mode=${type},tapif=${id}" ]
    ) interfaces
  );

  # TODO:
  # canShutdown = false;
  # shutdownCommand =
  #   throw "'crosvm stop' is not graceful";
}
