{ config, lib, ... }:
let
  inherit (config) root version;
  claude = root + "/integrations/claude";
  manifest = lib.importJSON (claude + "/.claude-plugin/plugin.json");
in
{
  perSystem = { pkgs, self', ... }: {
    packages.claudePlugin = pkgs.runCommand "nitpick-claude-plugin-${version}" { } ''
      mkdir -p $out/.claude-plugin $out/hooks $out/bin
      cp ${claude + "/.claude-plugin/plugin.json"} $out/.claude-plugin/plugin.json
      cp ${claude + "/hooks/hooks.json"} $out/hooks/hooks.json
      cp ${claude + "/hooks/register.js"} $out/hooks/register.js
      cp ${root + "/integrations/pi/bridge.ts"} $out/bridge.ts
      substitute ${claude + "/bridge-helper.ts"} $out/bridge-helper.ts \
        --replace-fail '"../pi/bridge.ts"' '"./bridge.ts"'
      substitute ${claude + "/bin/nitpick-bridge"} $out/bin/nitpick-bridge \
        --replace-fail 'exec node ' 'exec ${pkgs.nodejs_24}/bin/node '
      chmod +x $out/bin/nitpick-bridge
    '';

    # Claude Code reads the version from plugin.json itself, so it has to match.
    checks.claudeVersion = pkgs.runCommand "nitpick-claude-version" { } (
      if manifest.version == version then "touch $out"
      else "echo 'integrations/claude/.claude-plugin/plugin.json has version ${manifest.version}, the flake ${version}' >&2; exit 1"
    );

    # The packaged bridge, started through the plugin's own entry point.
    checks.claude = pkgs.runCommand "nitpick-claude-tests" { nativeBuildInputs = [ pkgs.nodejs_24 ]; } ''
      NITPICK_CLAUDE_PLUGIN=${self'.packages.claudePlugin} node --test ${claude + "/bridge-helper.spec.ts"}
      touch $out
    '';
  };
}
