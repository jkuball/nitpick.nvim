{
  description = "Neovim-native code review for coding agents.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    import-tree.url = "github:denful/import-tree";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } ({ config, lib, ... }: {
    options.root = lib.mkOption {
      type = lib.types.path;
      default = ./.;
      readOnly = true;
    };

    options.version = lib.mkOption {
      type = lib.types.str;
      default = "0.1.0";
      readOnly = true;
    };

    imports = [
      inputs.flake-parts.flakeModules.modules
      (inputs.import-tree ./modules)
    ];

    config = {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      flake.nixvimModules = config.flake.modules.nixvim;
    };
  });
}
