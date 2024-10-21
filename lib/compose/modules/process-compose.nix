{ config, lib, pkgs, ... }:

{
  system.build = {
    process-compose-workflow = {
      version = "1.34";
      is_strict = true;

      processes = lib.concatMapAttrs (name: config:
        let
          inherit (config.networking) hostName;
          mainName = "${config.microvm.hypervisor}-${hostName}";
        in {
          ${mainName} = {
            command = "${config.microvm.declaredRunner}/bin/microvm-run";
            is_tty = true;
            namespace = hostName;
          };
      }) config.system.microvmConfigs;
    };

    process-compose-file = pkgs.writers.writeYAML "process-compose.yaml"
      config.system.build.process-compose-workflow;

    process-compose = pkgs.writeShellScript "process-compose.sh" ''
      #!${pkgs.runtimeShell} -e

      exec ${pkgs.process-compose}/bin/process-compose up -f ${config.system.build.process-compose-file}
    '';
  };
}
