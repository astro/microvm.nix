{ pkgs
, microvmConfig
, kernel ? pkgs.callPackage ../pkgs/microvm-kernel.nix {
  inherit (pkgs.linuxPackages_latest) kernel;
}
, bootDisk
, toplevel
}:

let
  inherit (pkgs) lib writeScriptBin;

  inherit (import ../lib { nixpkgs-lib = lib; }) createVolumesScript;

  hypervisorConfig = import (./runners + "/${microvmConfig.hypervisor}.nix") {
    inherit pkgs microvmConfig kernel bootDisk;
  };

  inherit (hypervisorConfig) command canShutdown shutdownCommand;
  preStart = hypervisorConfig.preStart or microvmConfig.preStart;
  
  runScriptBin = pkgs.writeScriptBin "microvm-run" ''
    #! ${pkgs.runtimeShell} -e

    ${createVolumesScript pkgs microvmConfig.volumes}
    ${preStart}

    exec ${command}
  '';

  shutdownScriptBin = pkgs.writeScriptBin "microvm-shutdown" ''
    #! ${pkgs.runtimeShell} -e

    ${shutdownCommand}
  '';

  consoleScriptBin = pkgs.writeScriptBin "microvm-console" ''
    #! ${pkgs.runtimeShell} -e

    ${hypervisorConfig.getConsoleScript}
    exec ${pkgs.screen}/bin/screen -S microvm-${microvmConfig.hostName} $PTY
  '';

  balloonScriptBin = pkgs.writeScriptBin "microvm-balloon" ''
    #! ${pkgs.runtimeShell} -e

    if [ -z "$1" ]; then
      echo "Usage: $0 <balloon-size-mb>"
      exit 1
    fi

    SIZE=$1
    ${hypervisorConfig.setBalloonScript}
  '';
in

pkgs.runCommand "microvm-${microvmConfig.hypervisor}-${microvmConfig.hostName}" {
  # for `nix run`
  meta.mainProgram = "microvm-run";
  passthru = {
    inherit canShutdown;
  };
} ''
  mkdir -p $out/bin

  ln -s ${runScriptBin}/bin/microvm-run $out/bin/microvm-run
  ${if canShutdown
    then "ln -s ${shutdownScriptBin}/bin/microvm-shutdown $out/bin/microvm-shutdown"
    else ""}
  ${lib.optionalString ((hypervisorConfig.getConsoleScript or null) != null) ''
    ln -s ${consoleScriptBin}/bin/microvm-console $out/bin/microvm-console
  ''}
  ${lib.optionalString ((hypervisorConfig.setBalloonScript or null) != null) ''
    ln -s ${balloonScriptBin}/bin/microvm-balloon $out/bin/microvm-balloon
  ''}

  mkdir -p $out/share/microvm
  ln -s ${toplevel} $out/share/microvm/system

  ${lib.concatMapStringsSep " " (interface:
    lib.optionalString (interface.type == "tap" && interface ? id) ''
      echo "${interface.id}" >> $out/share/microvm/tap-interfaces
    '') microvmConfig.interfaces}

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
