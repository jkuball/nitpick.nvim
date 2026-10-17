{
  perSystem = { pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = [
        pkgs.neovim # tests/nvim_test.lua
        pkgs.nodejs_24 # the integrations' tests
        pkgs.nixpkgs-fmt
      ];
    };

    formatter = pkgs.nixpkgs-fmt;
  };
}
