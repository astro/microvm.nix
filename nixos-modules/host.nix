{ pkgs, ... }:
let
  stateDir = "/var/lib/microvms";
  microvmCommand = import ../pkgs/microvm-command.nix {
    inherit pkgs;
  };
in
{
  system.activationScripts.microvm-host = ''
    mkdir -p ${stateDir}
    chown root:kvm ${stateDir}
    chmod g+w ${stateDir}
  '';

  environment.systemPackages = with pkgs; [
    microvmCommand
  ];

  users.users.microvm = {
    isSystemUser = true;
    group = "kvm";
  };

  systemd.services."microvm@" = {
    description = "MicroVM '%i'";
    after = [ "network.target" ];
    unitConfig.ConditionPathExists = "${stateDir}/%i/microvm-run";
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "${stateDir}/%i";
      ExecStart = "${stateDir}/%i/microvm-run";
      ExecStop = "${stateDir}/%i/microvm-shutdown";
      Restart = "always";
      RestartSec = "1s";
      User = "microvm";
      Group = "kvm";
    };
  };
}
