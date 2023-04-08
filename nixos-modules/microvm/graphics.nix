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
in
lib.mkIf config.microvm.graphics.enable {
  environment.systemPackages = with pkgs; [
    run-sommelier run-wayland-proxy
  ];
}
