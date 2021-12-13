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
, hostName
, socket ? "microvm-${hostName}.firecracker"
, ...
}@args:
let
  config = args // {
    inherit interfaces;
  };
  pkgs = nixpkgs.legacyPackages.${system};
  firectl = pkgs.firectl.overrideAttrs (_oa: {
    # allow read-only root-drive
    postPatch = ''
      substituteInPlace options.go \
          --replace "IsReadOnly:   firecracker.Bool(false)," \
          "IsReadOnly:   firecracker.Bool(true),"
      '';
    });
in config // {
  command = nixpkgs.lib.escapeShellArgs (
    [
      "${firectl}/bin/firectl"
      "--firecracker-binary=${pkgs.firecracker}/bin/firecracker"
      "-m" (toString mem)
      "-c" (toString vcpu)
      "--kernel=${nixos.config.system.build.kernel.dev}/vmlinux"
      "--kernel-opts=console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ro quiet init=${nixos.config.system.build.toplevel}/init ${append}"
      "--root-drive=${rootDisk}"
    ] ++
    (if socket != null then [ "-s" socket ] else []) ++
    map ({ image, ... }:
      "--add-drive=${image}:rw"
    ) volumes ++
    map (_:
      throw "virtiofs shares not implemented for CrosVM"
    ) shares ++
    map ({ type ? "tap", id, mac }:
      if type == "tap"
      then "--tap-device=${id}/${mac}"
      else throw "Unsupported interface type ${type} for Firecracker"
    ) interfaces
  );

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then nixpkgs.lib.escapeShellArgs [
      "${pkgs.curl}/bin/curl"
      "--unix-socket" socket
      "-X" "PUT" "http://localhost/actions"
      "-H"  "Accept: application/json"
      "-H"  "Content-Type: application/json"
      "-d" (builtins.toJSON {
        action_type = "SendCtrlAltDel";
      })
    ]
    else throw "Cannot shutdown without socket";
}
