{ pkgs
, microvmConfig
, toplevel
}:

let
  inherit (pkgs) lib;

  inherit (import ./. { nixpkgs-lib = lib; }) createVolumesScript makeMacvtap;
  inherit (makeMacvtap {
    inherit microvmConfig hypervisorConfig;
  }) openMacvtapFds macvtapFds;

  hypervisorConfig = import (./runners + "/${microvmConfig.hypervisor}.nix") {
    inherit pkgs microvmConfig macvtapFds;
  };

  inherit (hypervisorConfig) command canShutdown shutdownCommand;
  supportsNotifySocket = hypervisorConfig.supportsNotifySocket or false;
  preStart = hypervisorConfig.preStart or microvmConfig.preStart;
  tapMultiQueue = hypervisorConfig.tapMultiQueue or false;

  execArg = lib.optionalString microvmConfig.prettyProcnames
    ''-a "microvm@${microvmConfig.hostName}"'';

  runScriptBin = pkgs.writeShellScriptBin "microvm-run" ''
    ${preStart}
    ${createVolumesScript pkgs.buildPackages microvmConfig.volumes}
    ${lib.optionalString (hypervisorConfig.requiresMacvtapAsFds or false) openMacvtapFds}

    exec ${execArg} ${command}
  '';

  shutdownScriptBin = pkgs.writeShellScriptBin "microvm-shutdown" ''
    ${shutdownCommand}
  '';

  balloonScriptBin = pkgs.writeShellScriptBin "microvm-balloon" ''
    set -e

    if [ -z "$1" ]; then
      echo "Usage: $0 <balloon-size-mb>"
      exit 1
    fi

    SIZE=$1
    ${hypervisorConfig.setBalloonScript}
  '';
in

pkgs.buildPackages.runCommand "microvm-${microvmConfig.hypervisor}-${microvmConfig.hostName}"
{
  # for `nix run`
  meta.mainProgram = "microvm-run";
  passthru = {
    inherit canShutdown supportsNotifySocket;
    inherit (microvmConfig) hypervisor;
  };
} ''
  mkdir -p $out/bin

  ln -s ${runScriptBin}/bin/microvm-run $out/bin/microvm-run
  ${if canShutdown
    then "ln -s ${shutdownScriptBin}/bin/microvm-shutdown $out/bin/microvm-shutdown"
    else ""}
  ${lib.optionalString ((hypervisorConfig.setBalloonScript or null) != null) ''
    ln -s ${balloonScriptBin}/bin/microvm-balloon $out/bin/microvm-balloon
  ''}

  mkdir -p $out/share/microvm
  ln -s ${toplevel} $out/share/microvm/system

  echo vnet_hdr > $out/share/microvm/tap-flags
  ${lib.optionalString tapMultiQueue ''
    echo multi_queue >> $out/share/microvm/tap-flags
  ''}
  ${lib.concatMapStringsSep " " (interface:
    lib.optionalString (interface.type == "tap" && interface ? id) ''
      echo "${interface.id}" >> $out/share/microvm/tap-interfaces
    '') microvmConfig.interfaces}

  ${lib.concatMapStringsSep " " (interface:
    lib.optionalString (
      interface.type == "macvtap" &&
      interface ? id
    ) (
      if interface.macvtap.link or null == null
      then throw "microvm.interface's macvtap.link must be specified for id=${interface.id}"
      else if interface.macvtap.mode or null == null
      then throw "microvm.interface's macvtap.mode must be specified for id=${interface.id}"
      else ''
        echo "${builtins.concatStringsSep " " [
          interface.id
          interface.mac
          interface.macvtap.link
          (builtins.toString interface.macvtap.mode)
        ]}" >> $out/share/microvm/macvtap-interfaces
      ''
    )) microvmConfig.interfaces}


  ${lib.concatMapStrings ({ tag, socket, source, proto, ... }:
      lib.optionalString (proto == "virtiofs") ''
        mkdir -p $out/share/microvm/virtiofs/${tag}
        echo "${socket}" > $out/share/microvm/virtiofs/${tag}/socket
        echo "${source}" > $out/share/microvm/virtiofs/${tag}/source
      ''
    ) microvmConfig.shares}

  ${lib.concatMapStrings ({ bus, path, ... }: ''
    echo "${path}" >> $out/share/microvm/${bus}-devices
  '') microvmConfig.devices}
''
