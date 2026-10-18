{ config, lib, ... }:
let
  inherit (config) root version;
in
{
  perSystem = { pkgs, self', ... }: {
    packages.vimPlugin = pkgs.vimUtils.buildVimPlugin {
      pname = "nitpick.nvim";
      inherit version;
      src = lib.fileset.toSource {
        inherit root;
        fileset = lib.fileset.unions [
          (root + "/lua")
          (root + "/plugin")
          (root + "/ftplugin")
          (root + "/doc")
          (root + "/LICENSE")
          (root + "/README.md")
        ];
      };
      meta = {
        description = "Neovim-native code review for coding agents.";
        license = lib.licenses.mit;
        platforms = lib.platforms.unix;
      };
    };

    packages.default = self'.packages.vimPlugin;

    checks.nvim = pkgs.runCommand "nitpick-nvim-tests"
      { nativeBuildInputs = [ pkgs.neovim ]; }
      ''
        export HOME=$TMPDIR
        NITPICK_PLUGIN=${self'.packages.vimPlugin} \
          nvim --clean --headless -l ${root + "/tests/nvim_test.lua"}
        touch $out
      '';
  };
}
