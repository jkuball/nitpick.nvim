{
  perSystem = { pkgs, self', ... }: {
    packages.nvim = pkgs.neovim.override {
      configure = {
        customLuaRC = builtins.readFile ./init.lua;
        packages.nitpick.start = [ self'.packages.vimPlugin ];
      };
    };

    apps.default = {
      type = "app";
      program = "${self'.packages.nvim}/bin/nvim";
      meta.description = "Neovim with nitpick and its suggested mappings";
    };

    checks.nvimTry = pkgs.runCommand "nitpick-nvim-try" { } ''
      export HOME=$TMPDIR
      ${self'.packages.nvim}/bin/nvim --headless \
        -c 'if exists(":Nit") != 2 || maparg("gb", "n") !~ "nitpick" | cquit | endif' \
        -c 'qall'
      touch $out
    '';
  };
}
