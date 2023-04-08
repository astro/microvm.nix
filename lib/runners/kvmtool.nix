{ pkgs
, microvmConfig
, kernel
, bootDisk
}:

let
  inherit (pkgs) lib;
  inherit (microvmConfig) hostName vcpu mem balloonMem user interfaces volumes shares preStart devices;
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
        "-m" (toString (mem + balloonMem))
        "-c" (toString vcpu)
        "-d" "${bootDisk},ro"
        "--console" "virtio"
        "--rng"
        "-k" "${kernel}/${pkgs.stdenv.hostPlatform.linux-kernel.target}"
        "-p" "console=hvc0 reboot=k panic=1 nomodules ${toString microvmConfig.kernelParams}"
      ]
      ++
      lib.optionals (balloonMem > 0) [ "--balloon" ]
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

  setBalloonScript = ''
    if [[ $SIZE =~ ^-(\d+)$ ]]; then
      ARGS="-d ''${BASH_REMATCH[1]}"
    else
      ARGS="-i $SIZE"
    fi
    HOME=$PWD ${pkgs.kvmtool}/bin/lkvm balloon $ARGS -n ${hostName}
  '';
}
