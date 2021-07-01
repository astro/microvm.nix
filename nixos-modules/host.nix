{ pkgs, ... }:
let
  stateDir = "/var/lib/microvms";
in
{
  system.activationScripts.microvm-host = ''
    mkdir -p ${stateDir}
    chown root:kvm ${stateDir}
    chmod g+w ${stateDir}
  '';

  environment.systemPackages = [
    (import ../pkgs/microvm-command.nix {
      inherit pkgs;
    })
  ];

  users.users.microvm = {
    isSystemUser = true;
    group = "kvm";
  };

  systemd.services."microvm@" = {
    description = "MicroVM '%i'";
    after = [ "network.target" ];
    unitConfig.ConditionPathExists = "${stateDir}/%i/run";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${stateDir}/%i/run";
      ExecStop = "${stateDir}/%i/shutdown";
      Restart = "always";
      RestartSec = "1s";
      User = "microvm";
      Group = "kvm";
    };
  };
}
