{ self, lib }:

let
  nixosModulesPath = self.inputs.nixpkgs + "/nixos/modules";

in
{
  evalModules = args@{
    modules, specialArgs ? {}, system ? "x86_64-linux", ...
  }:
    lib.evalModules (args // {
      specialArgs = specialArgs // {
        microvm = self;
        system = specialArgs.system or system;
        # nixpkgs = specialArgs.nixpkgs or
        #   self.inputs.nixpkgs;
        pkgs = specialArgs.pkgs or
          self.inputs.nixpkgs.legacyPackages.${system};
      };
      modules = modules ++ [
        # ./modules/base.nix
        ./modules/options.nix
        ./modules/vms.nix
        ./modules/process-compose.nix
        # system.build
        (nixosModulesPath + "/system/build.nix")
      ];
    });
}
