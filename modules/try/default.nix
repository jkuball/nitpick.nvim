{
  perSystem = { pkgs, self', ... }: {
    packages.neovim = pkgs.neovim.override {
      configure = {
        customLuaRC = builtins.readFile ./init.lua;
        packages.nitpick.start = [ self'.packages.plugin ];
      };
    };

    apps.default = {
      type = "app";
      program = "${self'.packages.neovim}/bin/nvim";
      meta.description = "Neovim with nitpick and its suggested mappings";
    };

    checks.neovim = pkgs.runCommand "nitpick-neovim" { } ''
      export HOME=$TMPDIR
      ${self'.packages.neovim}/bin/nvim --headless \
        -c 'if exists(":Nit") != 2 || maparg("gb", "n") !~ "nitpick" | cquit | endif' \
        -c 'qall'
      touch $out
    '';
  };
}
