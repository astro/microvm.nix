{ pkgs
, config
, hypervisor
, preStart ? config.microvm.preStart
, command
, canShutdown ? false
, shutdownCommand ? throw "shutdownCommand not implemented"
}:

let
  inherit (import ../lib { nixpkgs-lib = pkgs.lib; }) createVolumesScript;
  
  run = ''
    #! ${pkgs.runtimeShell} -e

    ${createVolumesScript pkgs config.microvm.volumes}
    ${preStart}

    exec ${command}
  '';
  runScriptBin = pkgs.writeScriptBin "microvm-run" run;

  shutdown = ''
    #! ${pkgs.runtimeShell} -e

    ${shutdownCommand}
  '';
  shutdownScriptBin = pkgs.writeScriptBin "microvm-shutdown" shutdown;

in

pkgs.runCommandNoCC "microvm-${config.microvm.hypervisor}-${config.networking.hostName}" {
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
  ln -s ${config.system.build.toplevel} $out/share/microvm/system

  echo "${pkgs.lib.concatMapStringsSep " " (interface:
    if interface.type == "tap" && interface ? id
    then interface.id
    else ""
  ) config.microvm.interfaces}" > $out/share/microvm/tap-interfaces

  ${pkgs.lib.optionalString (config.microvm.shares != []) (
    pkgs.lib.concatMapStringsSep "\n" ({ tag, socket, source, proto, ... }:
      pkgs.lib.optionalString (proto == "virtiofs") ''
        mkdir -p $out/share/microvm/virtiofs/${tag}
        echo "${socket}" > $out/share/microvm/virtiofs/${tag}/socket
        echo "${source}" > $out/share/microvm/virtiofs/${tag}/source
      ''
    ) config.microvm.shares
  )}
''
