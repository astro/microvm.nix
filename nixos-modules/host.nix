# TODO: remove this file after 2024

{ lib, ... }:

lib.warn ''
  microvm.nix/nixos-modules/host.nix has moved to
  microvm.nix/nixos-modules/host -- please update.
''
{
  imports = [ ./host ];
}
