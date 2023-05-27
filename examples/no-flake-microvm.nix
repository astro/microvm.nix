{ pkgs ? import <nixpkgs> {} }:

let
  hypervisor = "cloud-hypervisor";

  hypervisorsWith9p = [ "qemu" ];
  hypervisorsWithUserNet = [ "qemu" "kvmtool" ];

  configuration = { config, lib, ... }: {
    imports = [
      ../nixos-modules/microvm
    ];
    networking.hostName = "no-flake-microvm";
    users.users.root.password = "";
    services.getty.helpLine = ''
      Log in as "root" with an empty password.
    '';

    microvm = {
      hypervisor = hypervisor;
      # share the host's /nix/store if the hypervisor can do 9p
      shares = lib.optional (builtins.elem hypervisor hypervisorsWith9p) {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      };
      writableStoreOverlay = "/nix/.rw-store";
      volumes = [ {
        image = "nix-store-overlay.img";
        mountPoint = config.microvm.writableStoreOverlay;
        size = 2048;
      } ];
      interfaces = lib.optional (builtins.elem hypervisor hypervisorsWithUserNet) {
        type = "user";
        id = "qemu";
        mac = "02:00:00:01:01:01";
      };
    };
  };

  nixos = pkgs.nixos configuration;

in
nixos.config.microvm.declaredRunner
