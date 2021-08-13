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
, socket ? "microvm-${hostName}.cloud-hypervisor"
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
      "${pkgs.cloud-hypervisor}/bin/cloud-hypervisor"
      "--memory" "size=${toString mem}M,mergeable=on,shared=on"
      "--cpus" "boot=${toString vcpu}"
      "--rng" "--watchdog"
      "--console" "tty"
      "--kernel" "${nixos.config.system.build.kernel.dev}/vmlinux"
      "--cmdline" "console=hvc0 quiet reboot=t panic=-1 ro root=/dev/vda init=${nixos.config.system.build.toplevel}/init ${append}"
      "--seccomp" "true"
      "--disk" "path=${rootDisk},readonly=on"
    ] ++
    map ({ image, ... }:
      "path=${image}"
    ) volumes ++
    (if shares != []
     then [ "--fs" ] ++
          (map ({ socket, tag, ... }:
            "tag=${tag},socket=${socket},dax=on"
          ) shares)
     else []) ++
    (if socket != null
     then [ "--api-socket" socket ]
     else []) ++
    (if interfaces != []
     then [ "--net" ] ++
          (map ({ type ? "tap", id, mac }:
            if type == "tap"
            then "tap=${id},mac=${mac}"
            else throw "Unsupported interface type ${type} for Cloud-Hypervisor"
          ) interfaces)
     else [])
  );

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then nixpkgs.lib.escapeShellArgs [
      "${pkgs.curl}/bin/curl"
      "--unix-socket" socket
      "-X" "PUT" "http://localhost/api/v1/vm.power-button"
    ]
    else throw "Cannot shutdown without socket";

  virtiofsDax = true;
}
