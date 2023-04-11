{ self, nixpkgs, system }:

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    # this runs as a MicroVM
    self.nixosModules.microvm

    ({ config, pkgs, ... }: {
      microvm = {
        hypervisor = "cloud-hypervisor";
        graphics.enable = true;
      };

      networking.hostName = "graphical-microvm";
      system.stateVersion = config.system.nixos.version;
      services.getty.helpLine = ''
        Log in as "root" with an empty password.
      '';
      users.users.root.password = "";
      users.users.user = {
        password = "";
        group = "user";
        isNormalUser = true;
        extraGroups = [ "video" ];
      };
      users.groups.user = {};
      environment.systemPackages = with pkgs; [
        hello-wayland
      ];

      systemd.services.hello-wayland = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "user";
          Group = "user";
        };
        script = ''
          while ! [ -e /dev/dri/card0 ] ; do
            sleep 1
          done

          export XDG_RUNTIME_DIR=/tmp
          PATH=/run/current-system/sw/bin
          exec run-wayland-proxy hello-wayland
        '';
      };
    })
  ];
}
