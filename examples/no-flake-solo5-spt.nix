{ pkgs ? import <nixpkgs> { } }:

let
  unikernel = pkgs.stdenv.mkDerivation {
    pname = "test_net";
    buildInputs = [ pkgs.solo5 ];
    inherit (pkgs.solo5) version src;
    dontConfigure = true;
    dontInstall = true;
    dontFixup = true;
    buildPhase = ''
      cd tests/test_net
      solo5-elftool gen-manifest manifest.json manifest.c
      x86_64-solo5-none-static-cc -c manifest.c -o manifest.o
      x86_64-solo5-none-static-cc -c test_net.c -o test.o
      mkdir $out
      x86_64-solo5-none-static-ld -z solo5-abi=spt *.o -o $out/$pname.spt
    '';
  };

  hypervisor = "solo5-spt";

  configuration = { config, lib, ... }: {
    imports = [ ../nixos-modules/microvm ];
    networking.hostName = "no-flake-solo5-spt";

    microvm = {
      inherit hypervisor;
      mem = 8;
      interfaces = [{
        type = "tap";
        id = "tap0";
        guestId = "service0";
        mac = "02:00:00:01:01:01";
      }];
      kernel = "${unikernel}/test_net.spt";
    };
  };

  nixos = pkgs.nixos configuration;

in nixos.config.microvm.declaredRunner
