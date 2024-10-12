{ config, pkgs, ... }:

{
  system.build = {
    process-compose-workflow = {
      version = "1.34";

      processes = builtins.mapAttrs (name: runner: {
        command = "${runner}/bin/microvm-run";
      }) config.system.microvmRunners;
    };

    process-compose-file = pkgs.writers.writeYAML "process-compose.yaml"
      config.system.build.process-compose-workflow;

    process-compose = pkgs.writeShellScript "process-compose.sh" ''
      #!${pkgs.runtimeShell} -e

      exec ${pkgs.process-compose}/bin/process-compose up -f ${config.system.build.process-compose-file}
    '';
  };
}
