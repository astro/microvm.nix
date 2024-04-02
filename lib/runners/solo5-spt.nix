{ pkgs, microvmConfig, macvtapFds }:

let
  inherit (pkgs) lib;
  inherit (microvmConfig) mem interfaces volumes kernel kernelParams;
in {
  command = builtins.concatStringsSep " "
    ([ (lib.meta.getExe' pkgs.solo5 "solo5-spt") "--mem=${toString mem}" ]

      ++ (builtins.concatMap ({ type, id, guestId, mac, ... }:
        assert type == "tap";
        assert guestId != null; [
          "--net:${guestId}=${id}"
          "--net-mac:${guestId}=${mac}"
        ]) interfaces)

      ++ (map ({ label, image, ... }:
        assert label != null;
        "--block:${label}=${image}") volumes)

      ++ [ kernel ] ++ kernelParams);

  canShutdown = false;
}
