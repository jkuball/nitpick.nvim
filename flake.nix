{
  description = "Neovim-native code review for coding agents.";

  nixConfig = {
    extra-substituters = [ "https://jkuball.cachix.org" ];
    extra-trusted-public-keys = [ "jkuball.cachix.org-1:+9CHwNss+Andi72M3ZruI40RLYvYkyQAcT0ou4P50m0=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    import-tree.url = "github:denful/import-tree";
    presswerk.url = "github:jkuball/presswerk/v0.5.0";
  };

  outputs = inputs@{ self, ... }: inputs.flake-parts.lib.mkFlake { inherit inputs; } ({ lib, ... }: {
    options.root = lib.mkOption {
      type = lib.types.path;
      default = ./.;
      readOnly = true;
    };

    imports = [ (inputs.import-tree ./modules) ];

    config = {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      flake.presswerk.default = inputs.presswerk.lib.mkRelease {
        sourceRoot = self.outPath;
        versionFiles.json = {
          package = {
            path = "package.json";
            key = "version";
          };
          claude-plugin = {
            path = "integrations/claude/.claude-plugin/plugin.json";
            key = "version";
          };
        };
        versionFiles.badge.default = { };
        publishers.github-release.default.repository = "jkuball/nitpick.nvim";
      };
    };
  });
}
