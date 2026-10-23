{
  description = "T3 Code stable releases with direnv support";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      packageNames = lib.attrNames (
        lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists ./packages/${name}/package.nix
        ) (builtins.readDir ./packages)
      );

      # A package that replaces a nixpkgs package of the same name receives
      # the nixpkgs one, so it can override it instead of repeating it.
      callPackages =
        final: prev:
        lib.genAttrs packageNames (
          name:
          final.callPackage ./packages/${name}/package.nix (
            lib.optionalAttrs (prev ? ${name}) { ${name} = prev.${name}; }
          )
        );
    in
    {
      overlays.default = callPackages;

      packages = forAllSystems (
        pkgs:
        callPackages pkgs pkgs
        // {
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
        }
      );

      nixosModules = {
        t3code-os =
          { lib, pkgs, ... }:
          {
            imports = [ ./modules/nixos/t3code-os.nix ];
            services.t3code-os.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
          };
        default = self.nixosModules.t3code-os;
      };

      checks = forAllSystems (pkgs: {
        t3code-os = pkgs.testers.runNixOSTest (import ./checks/t3code-os.nix { inherit self; });
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
