{ pkgs
, microvmConfig
, kernel ? pkgs.callPackage ../pkgs/microvm-kernel.nix {
  inherit (pkgs.linuxPackages_latest) kernel;
}
, rootDisk
, toplevel
}:

let
  inherit (import ../lib { nixpkgs-lib = pkgs.lib; }) createVolumesScript;

  hypervisorConfig = import (./runners + "/${microvmConfig.hypervisor}.nix") {
    inherit pkgs microvmConfig kernel rootDisk;
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

in

pkgs.runCommandNoCC "microvm-${microvmConfig.hypervisor}-${microvmConfig.hostName}" {
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

  mkdir -p $out/share/microvm
  ln -s ${toplevel} $out/share/microvm/system

  ${pkgs.lib.concatMapStringsSep " " (interface:
    pkgs.lib.optionalString (interface.type == "tap" && interface ? id) ''
      echo "${interface.id}" >> $out/share/microvm/tap-interfaces
    '') microvmConfig.interfaces}

  ${pkgs.lib.concatMapStrings ({ tag, socket, source, proto, ... }:
      pkgs.lib.optionalString (proto == "virtiofs") ''
        mkdir -p $out/share/microvm/virtiofs/${tag}
        echo "${socket}" > $out/share/microvm/virtiofs/${tag}/socket
        echo "${source}" > $out/share/microvm/virtiofs/${tag}/source
      ''
    ) microvmConfig.shares}

  ${pkgs.lib.concatMapStrings ({ bus, path, ... }: ''
    echo "${path}" >> $out/share/microvm/${bus}-devices
  '') microvmConfig.devices}
''
