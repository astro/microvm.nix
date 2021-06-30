{ self, nixpkgs }:

{ system
, vcpu
, mem
, nixos
, append
, interfaces ? []
, rootDisk
, volumes
, hostName
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
      "--memory" "size=${toString mem}M,mergeable=on"
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
    builtins.concatMap ({ type ? "tap", id, mac }:
      if type == "tap"
      then [ "--net" "tap=${id},mac=${mac}" ]
      else throw "Unsupported interface type ${type} for Cloud-Hypervisor"
    ) interfaces
  );
}
