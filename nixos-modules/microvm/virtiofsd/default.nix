{ config, lib, pkgs, ... }:

let
  virtiofsShares = builtins.filter ({ proto, ... }:
    proto == "virtiofs"
  ) config.microvm.shares;

  requiresVirtiofsd = virtiofsShares != [];

  inherit (pkgs.python3Packages) supervisor;
  supervisord = lib.getExe' supervisor "supervisord";
  supervisorctl = lib.getExe' supervisor "supervisorctl";

in
{
  microvm.virtiofsdScripts = lib.mkIf requiresVirtiofsd {
    run =
      let
        supervisordConfig = pkgs.writeText "${config.networking.hostName}-virtiofsd-supervisord.conf" ''
          [supervisord]
          nodaemon=true

          [eventlistener:notify]
          command=${pkgs.writers.writePython3 "supervisord-event-handler" { } (
                 pkgs.substituteAll {
                   src = ./supervisord-event-handler.py;
                   virtiofsdCount = builtins.length virtiofsShares;
                 }
               )}
          events=PROCESS_STATE

          ${lib.concatMapStrings ({ proto, tag, socket, source, ... }: ''
            [program:virtiofsd-${tag}]
            stderr_syslog=true
            stdout_syslog=true
            autorestart=true
            command=${pkgs.writeShellScript "virtiofsd-${tag}" ''
              if [ $(id -u) = 0 ]; then
                OPT_RLIMIT="--rlimit-nofile 1048576"
              else
                OPT_RLIMIT=""
              fi
              exec ${lib.getExe pkgs.virtiofsd} \
                --socket-path=${lib.escapeShellArg socket} \
                --socket-group=$(id -gn) \
                --shared-dir=${lib.escapeShellArg source} \
                $OPT_RLIMIT \
                --thread-pool-size ${toString config.microvm.virtiofsd.threadPoolSize} \
                --posix-acl --xattr \
                ${lib.optionalString (config.microvm.virtiofsd.inodeFileHandles != null)
                  "--inode-file-handles=${config.microvm.virtiofsd.inodeFileHandles}"
                 } \
                ${lib.concatStringsSep " " config.microvm.virtiofsd.extraArgs}
              ''}
          '' ) virtiofsShares}
        '';
      in pkgs.writeShellScriptBin "run-virtiofsd" ''
        exec ${supervisord} --configuration ${supervisordConfig}
      '';

    reload = pkgs.writeShellScriptBin "reload-virtiofsd" ''
      exec ${supervisorctl} reload
    '';

    shutdown = pkgs.writeShellScriptBin "shutdown-virtiofsd" ''
      exec ${supervisorctl} stop
    '';
  };
}
