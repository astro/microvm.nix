{ config, lib, pkgs, ... }:

let
  # TODO: did not get sommelier to work
  run-sommelier = with pkgs; writeScriptBin "run-sommelier" ''
    #!${runtimeShell} -e
    exec ${sommelier}/bin/sommelier --virtgpu-channel -- $@
  '';
  # Working: run Wayland applications prefixed with `run-wayland-proxy`
  run-wayland-proxy = with pkgs; writeScriptBin "run-wayland-proxy" ''
    #!${runtimeShell} -e
    exec ${wayland-proxy-virtwl}/bin/wayland-proxy-virtwl --virtio-gpu -- $@
  '';
  # Waypipe. Needs `microvm#waypipe-client` on the host.
  run-waypipe = with pkgs; writeScriptBin "run-waypipe" ''
    #!${runtimeShell} -e
    exec ${waypipe}/bin/waypipe --vsock -s 2:6000 server $@
  '';
in
lib.mkIf config.microvm.graphics.enable {
  boot.kernelModules = [ "drm" "virtio_gpu" ];

  environment.systemPackages = with pkgs; [
    run-sommelier run-wayland-proxy run-waypipe
  ];
}
