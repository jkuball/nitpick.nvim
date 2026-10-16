{
  description = "nitpick.nvim: nitpick your coding agent from Neovim (Pi, Claude Code)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self
    , nixpkgs
    , ...
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      version = "0.1.0";

      packagesFor = pkgs: {
        # Neovim plugin (lua/, plugin/, doc/).
        vimPlugin = pkgs.vimUtils.buildVimPlugin {
          pname = "nitpick.nvim";
          inherit version;
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./lua
              ./plugin
              ./doc
              ./LICENSE
              ./README.md
            ];
          };
          meta = {
            description = "Write code reviews in Neovim and send them to a running Pi or Claude Code session";
            license = lib.licenses.mit;
            platforms = lib.platforms.unix;
          };
        };

        # Claude Code plugin (a mod); load it with --plugin-dir or CLAUDE_CODE_PLUGIN_DIRS.
        claudePlugin = pkgs.runCommand "nitpick-claude-plugin-${version}" { } ''
          mkdir -p $out/.claude-plugin $out/hooks $out/bin
          cp ${./integrations/claude/.claude-plugin/plugin.json} $out/.claude-plugin/plugin.json
          cp ${./integrations/claude/hooks/hooks.json} $out/hooks/hooks.json
          cp ${./integrations/claude/hooks/register.js} $out/hooks/register.js
          cp ${./integrations/pi/bridge.ts} $out/bridge.ts
          substitute ${./integrations/claude/bridge-helper.ts} $out/bridge-helper.ts \
            --replace-fail '"../pi/bridge.ts"' '"./bridge.ts"'
          substitute ${./integrations/claude/bin/nitpick-bridge} $out/bin/nitpick-bridge \
            --replace-fail 'exec node ' 'exec ${pkgs.nodejs_24}/bin/node '
          chmod +x $out/bin/nitpick-bridge
        '';

        # Pi extension; load "${piExtension}/index.ts".
        piExtension = pkgs.runCommand "nitpick-pi-extension-${version}" { } ''
          mkdir -p $out
          cp ${./integrations/pi/index.ts} $out/index.ts
          cp ${./integrations/pi/bridge.ts} $out/bridge.ts
        '';
      };
    in
    {
      packages = forAllSystems (pkgs: packagesFor pkgs // { default = (packagesFor pkgs).vimPlugin; });

      overlays.default = final: prev: {
        vimPlugins = prev.vimPlugins // {
          nitpick-nvim = (packagesFor final).vimPlugin;
        };
        nitpick-pi-extension = (packagesFor final).piExtension;
        nitpick-claude-plugin = (packagesFor final).claudePlugin;
      };

      # nixvim: imports = [ inputs.nitpick.nixvimModules.default ];
      nixvimModules.default =
        { pkgs, ... }:
        {
          extraPlugins = [ self.packages.${pkgs.stdenv.hostPlatform.system}.vimPlugin ];
        };

      homeModules = {
        # Home Manager with lukasl-dev/pi.nix: imports = [ inputs.nitpick.homeModules.pi ];
        pi =
          { pkgs, ... }:
          {
            programs.pi.coding-agent.extensions = [
              "${self.packages.${pkgs.stdenv.hostPlatform.system}.piExtension}/index.ts"
            ];
          };

        # Home Manager's programs.claude-code; needs Claude Code >= 2.1.287 (mods).
        claude-code =
          { pkgs, ... }:
          {
            programs.claude-code.settings.env.CLAUDE_CODE_PLUGIN_DIRS =
              "${self.packages.${pkgs.stdenv.hostPlatform.system}.claudePlugin}";
          };

        default = self.homeModules.pi;
      };

      checks = forAllSystems (
        pkgs:
        let
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./lua
              ./plugin
              ./doc
              ./integrations
              ./tests
            ];
          };
          own = self.packages.${pkgs.stdenv.hostPlatform.system};
        in
        {
          nvim = pkgs.runCommand "nitpick-nvim-tests" { nativeBuildInputs = [ pkgs.neovim ]; } ''
            cp -r ${src} repo && chmod -R u+w repo && cd repo
            export HOME=$TMPDIR
            nvim --clean --headless -l tests/nvim_test.lua
            touch $out
          '';

          bridge = pkgs.runCommand "nitpick-bridge-tests" { nativeBuildInputs = [ pkgs.nodejs_24 ]; } ''
            cd ${src}
            node --test integrations/pi/bridge.test.ts integrations/pi/index.test.ts integrations/claude/bridge-helper.spec.ts
            touch $out
          '';

          inherit (own) vimPlugin piExtension claudePlugin;
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
