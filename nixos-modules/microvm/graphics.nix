{ config, lib, pkgs, ... }:

let
  # TODO: did not get sommelier to work
  run-sommelier = with pkgs; writeShellScriptBin "run-sommelier" ''
    exec ${lib.getExe sommelier} --virtgpu-channel -- $@
  '';
  # Working: run Wayland applications prefixed with `run-wayland-proxy`
  run-wayland-proxy = with pkgs; writeShellScriptBin "run-wayland-proxy" ''
    exec ${lib.getExe wayland-proxy-virtwl} --virtio-gpu -- $@
  '';
  # Waypipe. Needs `microvm#waypipe-client` on the host.
  run-waypipe = with pkgs; writeShellScriptBin "run-waypipe" ''
    exec ${lib.getExe waypipe}/bin/waypipe --vsock -s 2:6000 server $@
  '';
in
lib.mkIf config.microvm.graphics.enable {
  boot.kernelModules = [ "drm" "virtio_gpu" ];

  environment.systemPackages = with pkgs; [
    #run-sommelier
    run-wayland-proxy
    run-waypipe
  ];
}
