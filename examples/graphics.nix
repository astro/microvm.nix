{ self, nixpkgs, system
, packages ? ""
, tapInterface ? null
}:

nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    # this runs as a MicroVM
    self.nixosModules.microvm

    ({ config, lib, pkgs, ... }: {
      microvm = {
        hypervisor = "cloud-hypervisor";
        graphics.enable = true;
        interfaces = lib.optional (tapInterface != null) {
          type = "tap";
          id = tapInterface;
          mac = "00:00:00:00:00:02";
        };
      };

      networking.hostName = "graphical-microvm";
      system.stateVersion = config.system.nixos.version;
      nixpkgs.overlays = [ self.overlay ];

      services.getty.autologinUser = "user";
      users.users.user = {
        password = "";
        group = "user";
        isNormalUser = true;
        extraGroups = [ "wheel" "video" ];
      };
      users.groups.user = {};
      security.sudo = {
        enable = true;
        wheelNeedsPassword = false;
      };

      environment.sessionVariables = {
        WAYLAND_DISPLAY = "wayland-1";
        DISPLAY = ":0";
        QT_QPA_PLATFORM = "wayland"; # Qt Applications
        GDK_BACKEND = "wayland"; # GTK Applications
        XDG_SESSION_TYPE = "wayland"; # Electron Applications
        SDL_VIDEODRIVER = "wayland";
        CLUTTER_BACKEND = "wayland";
      };

      systemd.user.services.wayland-proxy = {
        enable = true;
        description = "Wayland Proxy";
        serviceConfig = with pkgs; {
          # Environment = "WAYLAND_DISPLAY=wayland-1";
          ExecStart = "${wayland-proxy-virtwl}/bin/wayland-proxy-virtwl --virtio-gpu --x-display=0 --xwayland-binary=${xwayland}/bin/Xwayland";
          Restart = "on-failure";
          RestartSec = 5;
        };
        wantedBy = [ "default.target" ];
      };

      environment.systemPackages = with pkgs; [
        xdg-utils # Required
      ] ++ map (package:
        lib.attrByPath (lib.splitString "." package) (throw "Package ${package} not found in nixpkgs") pkgs
      ) (
        builtins.filter (package:
          package != ""
        ) (lib.splitString " " packages));

      hardware.opengl.enable = true;
    })
  ];
}
