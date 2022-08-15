{ pkgs
, microvmConfig
, kernel
, rootDisk
}:

let
  inherit (pkgs) lib;
  inherit (microvmConfig) hostName vcpu mem user interfaces volumes shares preStart devices;
in {
  preStart = ''
    ${preStart}
    export HOME=$PWD
  '';

  command =
    if user != null
    then throw "kvmtool will not change user"
    else lib.escapeShellArgs (
      [
        "${pkgs.kvmtool}/bin/lkvm" "run"
        "--name" hostName
        "-m" (toString mem)
        "-c" (toString vcpu)
        "-d" "${rootDisk},ro"
        "--console" "virtio"
        "--rng"
        "-k" "${kernel}/bzImage"
        "-p" "console=hvc0 reboot=k panic=1 nomodules ${toString microvmConfig.kernelParams}"
      ]
      ++
      builtins.concatMap ({ image, ... }:
        [ "-d" image ]
      ) volumes
      ++
      builtins.concatMap ({ proto, source, tag, ... }:
        if proto == "9p"
        then [
          "--9p" "${source},${tag}"
        ] else throw "virtiofs shares not implemented for kvmtool"
      ) shares
      ++
      builtins.concatMap ({ type, id, mac, ... }:
        if builtins.elem type [ "user" "tap" ]
        then [
          "-n" "mode=${type},tapif=${id},guest_mac=${mac}"
        ] else throw "interface type ${type} is not supported by kvmtool"
      ) interfaces
      ++
      map ({ bus, path }: {
        pci = "--vfio-pci=${path}";
        usb = throw "USB passthrough is not supported on kvmtool";
      }.${bus}) devices
    );

  # `lkvm stop` works but is not graceful.
  canShutdown = false;
}
